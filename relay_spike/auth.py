"""Minimal interactive Sign in with ChatGPT OAuth experiment for Relay.

No background authentication, no paid API key fallback, no ChatGPT cookie reuse.
Credentials are stored outside the repository in a 0600 file for this CLI spike.
Shipping macOS app must use Keychain, user controls, and a full security review.
"""
from __future__ import annotations

import base64
from contextlib import contextmanager
import fcntl
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import stat
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, urlopen
import uuid
import webbrowser

ISSUER = "https://auth.openai.com"
AUTHORIZE_URL = ISSUER + "/api/accounts/authorize"
TOKEN_URL = ISSUER + "/api/accounts/oauth/token"
DISCOVERY_URL = ISSUER + "/.well-known/openid-configuration"
RESOURCE = "https://api.openai.com/v1"
SCOPE = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
AUTH_PATH = "/auth/callback"
CONFIG_DIR = Path.home() / ".config" / "relay"
HOST_PATH = CONFIG_DIR / "spike-host.json"
TOKEN_PATH = CONFIG_DIR / "spike-oauth.json"
REQUIRED_PLAN_SCOPE = "chatgpt.tokens.use.direct"
REFRESH_SKEW_SECONDS = 60
# Per official Sign in with ChatGPT recovery guidance, these codes mean the
# rotating refresh token is no longer usable. Network/5xx are NOT terminal.
INVALID_REFRESH_CODES = frozenset({
    "invalid_grant", "invalid_refresh_token", "token_expired",
    "refresh_token_expired", "refresh_token_invalidated",
    "refresh_token_reused",
})


class AuthError(RuntimeError):
    """A sanitized authentication or permission failure."""


class UnusableRefreshToken(AuthError):
    """Only a confirmed terminal OAuth refresh error warrants token clearing."""


def _write_protected(path: Path, value: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if path.parent.is_symlink() or path.is_symlink():
        raise AuthError("Refusing to write credential data through a symlink.")
    os.chmod(path.parent, 0o700)
    fd, temp_path = tempfile.mkstemp(dir=path.parent, prefix=".relay-", text=True)
    try:
        os.chmod(temp_path, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(value, out)
            out.flush()
            os.fsync(out.fileno())  # Critical for crash-sensitive token rotation.
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def _read_protected(path: Path) -> dict | None:
    if not path.exists():
        return None
    if path.is_symlink():
        raise AuthError("Credential file must not be a symlink.")
    if path.stat().st_mode & 0o077:
        raise AuthError("Credential file permissions are too broad. Set mode 0600.")
    return json.loads(path.read_text(encoding="utf-8"))


def load_or_create_host() -> str:
    record = _read_protected(HOST_PATH)
    if record:
        host = record.get("ext_agent_host_id", "")
        if not isinstance(host, str) or not host.startswith("urn:uuid:"):
            raise AuthError("Invalid saved host ID.")
        return host
    host = "urn:uuid:" + str(uuid.uuid4())
    _write_protected(HOST_PATH, {"ext_agent_host_id": host})
    return host


def load_auth() -> dict:
    value = _read_protected(TOKEN_PATH)
    if not value:
        raise AuthError("Not signed in. Run: python3 -m relay_spike auth")
    return value


def _scoped_token(record: dict) -> str:
    """Fail closed without copying token content into error messages."""
    scopes = record.get("scopes")
    if not isinstance(scopes, list) or REQUIRED_PLAN_SCOPE not in scopes:
        raise AuthError("ChatGPT plan inference permission was not granted. Reauthorize.")
    token = record.get("access_token")
    if not isinstance(token, str) or not token.strip():
        raise AuthError("No plan-backed OAuth token. Run: python3 -m relay_spike auth")
    return token


def _nearing_expiry(record: dict) -> bool:
    try:
        saved_at = float(record["saved_at"])
        expires_in = float(record["expires_in"])
    except (TypeError, ValueError, KeyError):
        raise AuthError("Invalid saved OAuth expiry. Sign in again.") from None
    if saved_at <= 0 or expires_in <= 0:
        raise AuthError("Invalid saved OAuth expiry. Sign in again.")
    return time.time() >= saved_at + expires_in - REFRESH_SKEW_SECONDS


@contextmanager
def _refresh_lock():
    """Serialize rotating refresh grants between independent CLI processes.

    Lockfile remains on disk permanently: deleting/recreating it could allow
    separate inode locks to be held at the same time. Uses POSIX flock on Mac
    and Linux, with an owned regular file and no-follow open.
    """
    folder = TOKEN_PATH.parent
    folder.mkdir(parents=True, mode=0o700, exist_ok=True)
    if folder.is_symlink():
        raise AuthError("Refusing to lock credentials through a symlinked directory.")
    os.chmod(folder, 0o700)
    path = folder / (TOKEN_PATH.name + ".lock")
    flags = os.O_CREAT | os.O_RDWR
    if not hasattr(os, "O_NOFOLLOW"):
        raise AuthError("Secure refresh lock requires POSIX no-follow support.")
    flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError:
        raise AuthError("Could not securely open the OAuth refresh lock.") from None
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise AuthError("OAuth refresh lock must be an owner-only regular file.")
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def _clear_unusable_credentials(record: dict) -> None:
    """Retain only registration identity; clear failed rotating token secrets."""
    identity = {
        key: record[key] for key in (
            "client_id", "ext_agent_host_id", "subject"
        ) if isinstance(record.get(key), str) and record[key]
    }
    _write_protected(TOKEN_PATH, identity)


def _refresh_access_token(record: dict) -> str:
    """One token endpoint request, one atomic rotation, no inference retry."""
    old_refresh = record.get("refresh_token")
    client_id = record.get("client_id")
    if not isinstance(old_refresh, str) or not old_refresh.strip():
        raise AuthError("Saved session has no refresh token. Run: python3 -m relay_spike auth")
    if (not isinstance(client_id, str) or not client_id.strip()
            or client_id == "dynamic_agent_client"):
        raise AuthError("Missing issued OAuth client ID. Sign in again.")
    if "offline_access" not in record.get("scopes", []):
        raise AuthError("Offline refresh permission was not granted. Sign in again.")

    try:
        payload = request_json(
            TOKEN_URL,
            form={
                "grant_type": "refresh_token",
                "client_id": client_id,
                "refresh_token": old_refresh,
                "resource": RESOURCE,
            },
            refresh_errors=True,
        )
    except UnusableRefreshToken:
        _clear_unusable_credentials(record)
        raise AuthError(
            "ChatGPT session revoked or refresh token expired. "
            "Run: python3 -m relay_spike auth"
        ) from None
    access, scopes, lifetime = validate_token_fields(payload)
    replacement = payload.get("refresh_token")
    if (not isinstance(replacement, str) or not replacement.strip()
            or replacement == old_refresh):
        raise AuthError("OAuth refresh did not rotate the refresh token. Sign in again.")
    if REQUIRED_PLAN_SCOPE not in scopes or "offline_access" not in scopes:
        raise AuthError("Refresh did not grant required ChatGPT plan permissions. Reauthorize.")
    if payload.get("client_id", client_id) != client_id:
        raise AuthError("OAuth refresh returned a different client registration.")
    if access == record.get("access_token"):
        raise AuthError("OAuth refresh did not replace access credentials.")

    # Preserve the original verified ID-token identity as a returning sign-in
    # hint. Do not trust a refreshed ID token without a new identity check.
    new_record = {
        **record, "access_token": access, "refresh_token": replacement,
        "token_type": "Bearer", "scopes": scopes,
        "expires_in": lifetime, "saved_at": time.time(),
    }
    _write_protected(TOKEN_PATH, new_record)
    return access


def active_access_token() -> str:
    """Use existing access while valid; auto-rotate once near expiry.

    The second load *under* the cross-process lock handles another process
    already refreshing the token. No inference or browser sign-in is triggered.
    """
    record = load_auth()
    token = _scoped_token(record)
    if not _nearing_expiry(record):
        return token
    with _refresh_lock():
        fresh = load_auth()
        token = _scoped_token(fresh)
        if not _nearing_expiry(fresh):
            return token
        return _refresh_access_token(fresh)

def pkce_pair() -> tuple[str, str]:
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode("ascii")).digest()
    ).decode("ascii").rstrip("=")
    return verifier, challenge


def authorization_url(*, client_id: str, host_id: str, redirect_uri: str,
                      state: str, nonce: str, challenge: str) -> str:
    payload = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": SCOPE,
        "resource": RESOURCE,
        "state": state,
        "nonce": nonce,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
        "ext_agent_host_id": host_id,
    }
    if client_id == "dynamic_agent_client":
        payload["agent_name_hint"] = "Relay"
    return AUTHORIZE_URL + "?" + urlencode(payload)


def callback_state_is_valid(query: dict[str, list[str]], expected_state: str) -> bool:
    """Ignore unsolicited callbacks without terminating an active OAuth attempt."""
    states = query.get("state", [])
    return len(states) == 1 and hmac.compare_digest(states[0], expected_state)


def verify_callback(query: dict[str, list[str]], expected_state: str,
                    selected_client_id: str) -> tuple[str, str]:
    # An OAuth authorization code is one-time and must be bound to this attempt.
    if not callback_state_is_valid(query, expected_state):
        raise AuthError("OAuth state did not match.")
    if "error" in query:
        raise AuthError("User declined consent or authorization failed.")
    if len(query.get("code", [])) != 1 or not query["code"][0]:
        raise AuthError("OAuth callback had no authorization code.")
    callback_client_id = query.get("client_id", [])
    if len(callback_client_id) > 1:
        raise AuthError("Multiple client identifiers in callback.")
    if selected_client_id == "dynamic_agent_client":
        if len(callback_client_id) != 1 or callback_client_id[0] == selected_client_id:
            raise AuthError("Dynamic registration returned no issued client ID.")
        client_id = callback_client_id[0]
    else:
        if callback_client_id and callback_client_id[0] != selected_client_id:
            raise AuthError("Callback tried to switch OAuth client IDs.")
        client_id = selected_client_id
    return query["code"][0], client_id


def request_json(url: str, *, form: dict | None = None,
                 token: str | None = None, timeout: float = 20.0,
                 refresh_errors: bool = False) -> dict:
    data = urlencode(form).encode("utf-8") if form is not None else None
    headers = {"Accept": "application/json"}
    if form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    req = Request(url, data=data, headers=headers)
    try:
        with urlopen(req, timeout=timeout) as response:
            parsed = json.load(response)
    except HTTPError as exc:
        # Only the refresh endpoint needs machine-readable terminal errors.
        # Never echo raw response bodies or arbitrary server-supplied strings.
        if refresh_errors and url == TOKEN_URL:
            code = None
            try:
                failure = json.loads(exc.read(4096))
                if isinstance(failure, dict):
                    item = failure.get("error")
                    code = item if isinstance(item, str) else (
                        item.get("code") if isinstance(item, dict) else None
                    )
            except (ValueError, TypeError, OSError):
                pass
            if code in INVALID_REFRESH_CODES:
                raise UnusableRefreshToken("Refresh token is unusable.") from None
            if code == "invalid_client":
                raise AuthError(
                    "OAuth refresh client was rejected. Check client configuration."
                ) from None
        raise AuthError(f"OAuth/API request rejected (HTTP {exc.code}).") from None
    except (URLError, TimeoutError) as exc:
        raise AuthError("Network or timeout failure during authorization.") from None
    if not isinstance(parsed, dict):
        raise AuthError("Unexpected JSON object from identity/API service.")
    return parsed


def require_verification_dependencies():
    """Check before opening the browser; no half-finished login on missing PyJWT."""
    try:
        import jwt
        from jwt import PyJWKClient
    except ImportError:
        raise AuthError(
            "OIDC verification dependency missing. Run: "
            "python3 -m pip install -r requirements-spike.txt"
        ) from None
    return jwt, PyJWKClient


def verify_id_token(id_token: str, client_id: str, expected_nonce: str) -> dict:
    jwt, PyJWKClient = require_verification_dependencies()
    discovery = request_json(DISCOVERY_URL)
    if discovery.get("issuer") != ISSUER:
        raise AuthError("Unexpected OIDC issuer.")
    jwks_uri = discovery.get("jwks_uri", "")
    if not isinstance(jwks_uri, str) or not jwks_uri.startswith(ISSUER + "/"):
        raise AuthError("Unexpected JWKS endpoint.")
    try:
        key = PyJWKClient(jwks_uri).get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            key.key,
            algorithms=["RS256"],
            audience=client_id,
            issuer=ISSUER,
            options={"require": ["iss", "aud", "sub", "exp", "iat"]},
            leeway=5,
        )
    except jwt.PyJWTError as exc:
        raise AuthError("OIDC ID token verification failed.") from None
    if not isinstance(claims.get("nonce"), str) or not hmac.compare_digest(
        claims["nonce"], expected_nonce
    ):
        raise AuthError("OIDC nonce verification failed.")
    if not claims.get("sub"):
        raise AuthError("Missing verified user subject.")
    return claims


def validate_token_fields(tokens: dict) -> tuple[str, list[str], int]:
    """Fail closed on unusable or malformed OAuth token responses."""
    access_token = tokens.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise AuthError("Authorization returned no usable access token.")
    if tokens.get("token_type") != "Bearer":
        raise AuthError("Authorization returned an unexpected token type.")
    scope = tokens.get("scope", "")
    if not isinstance(scope, str):
        raise AuthError("Authorization returned invalid permission scopes.")
    try:
        lifetime = int(tokens.get("expires_in", 0))
    except (TypeError, ValueError):
        raise AuthError("Authorization returned invalid access token expiry.") from None
    if lifetime <= 0:
        raise AuthError("Authorization returned expired access token credentials.")
    return access_token, scope.split(), lifetime


def _callback_server(expected_state: str):
    result: dict = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:
            # Never print callback URLs, OAuth codes or browser-supplied fields.
            pass

        def do_GET(self) -> None:
            parsed = urlsplit(self.path)
            if parsed.path != AUTH_PATH:
                self.send_error(404)
                return
            # Reject stray local requests and DNS-rebinding Host headers.
            # Never let an unsolicited request consume the OAuth callback.
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
                self.send_error(400)
                return
            query = parse_qs(parsed.query, keep_blank_values=True)
            if not callback_state_is_valid(query, expected_state):
                self.send_error(400)
                return
            result["query"] = query
            body = b"Return to Relay in your terminal to finish sign-in."
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy", "default-src 'none'")
            self.end_headers()
            self.wfile.write(body)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = 1
    return server, result


def sign_in(timeout_seconds: float = 240.0) -> dict:
    require_verification_dependencies()
    host = load_or_create_host()
    existing = _read_protected(TOKEN_PATH)
    selected_client_id = existing.get("client_id") if existing else None
    selected_client_id = selected_client_id or "dynamic_agent_client"
    state, nonce = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    verifier, challenge = pkce_pair()
    server, result = _callback_server(state)
    redirect = f"http://127.0.0.1:{server.server_port}{AUTH_PATH}"
    url = authorization_url(
        client_id=selected_client_id, host_id=host, redirect_uri=redirect,
        state=state, nonce=nonce, challenge=challenge
    )
    try:
        print("Opening browser for ChatGPT sign-in. No API key is used.")
        if not webbrowser.open(url, new=2):
            raise AuthError("Could not open the system browser for sign-in.")
        deadline = time.monotonic() + timeout_seconds
        while "query" not in result and time.monotonic() < deadline:
            server.handle_request()
        if "query" not in result:
            raise AuthError("Authorization timed out without a callback.")
        code, issued_client_id = verify_callback(
            result["query"], state, selected_client_id
        )
    finally:
        server.server_close()

    tokens = request_json(
        TOKEN_URL,
        form={
            "grant_type": "authorization_code",
            "client_id": issued_client_id,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirect,
            "resource": RESOURCE,
        },
    )
    id_token = tokens.get("id_token")
    if not isinstance(id_token, str):
        raise AuthError("Missing OIDC identity token.")
    claims = verify_id_token(id_token, issued_client_id, nonce)
    if existing and existing.get("subject") != claims["sub"]:
        raise AuthError("Returning authorization selected a different ChatGPT account.")
    access_token, scopes, expires_in = validate_token_fields(tokens)
    if "offline_access" in scopes and (
        not isinstance(tokens.get("refresh_token"), str)
        or not tokens["refresh_token"].strip()
    ):
        raise AuthError("OAuth authorization omitted the renewable refresh token.")
    record = {
        "client_id": issued_client_id,
        "ext_agent_host_id": host,
        "subject": claims["sub"],
        "scopes": scopes,
        "id_token": id_token,
        "access_token": access_token,
        "refresh_token": tokens.get("refresh_token", ""),
        "expires_in": expires_in,
        "saved_at": time.time(),
    }
    with _refresh_lock():
        _write_protected(TOKEN_PATH, record)
    if REQUIRED_PLAN_SCOPE not in scopes:
        print("Signed in for identity, but ChatGPT plan usage was not authorized.")
    else:
        print("OAuth identity and ChatGPT plan permission verified.")
    return {"plan_usage_authorized": REQUIRED_PLAN_SCOPE in scopes}


def disconnect() -> None:
    with _refresh_lock():
        if TOKEN_PATH.exists() or TOKEN_PATH.is_symlink():
            if TOKEN_PATH.is_symlink():
                raise AuthError("Refusing to follow a symlink.")
            TOKEN_PATH.unlink()
    print("Local OAuth credentials deleted. Revoke Relay in ChatGPT Settings too.")
