"""Mandatory protected product OAuth factory. No legacy credential fallback.

Only the private first inherited frame supplies the account key/selection.
Model is the host's chosen current catalog slug; it is not an entitlement claim.
Import/construction do no account/network work. Explicit factory reads storage.
"""
from .account_bridge import read_bootstrap_fd,ProtectedAccountSession,AccountProtocolError
from .account_oauth import AccountOAuthService
from .oauth_answer_stream import OAuthAnswerStream

def protected_answer_stream(model,*,input_fd=0,service_factory=AccountOAuthService,client_factory=None):
    if (not isinstance(model,str) or not 0<len(model.encode())<=128 or not model.isascii()
        or model.startswith('-') or any(ord(c)<33 or ord(c)>126 for c in model)):
        raise AccountProtocolError('account_model_invalid')
    bootstrap=read_bootstrap_fd(input_fd,purpose='oauth_session')
    session=ProtectedAccountSession(bootstrap,service_factory=service_factory).open()
    return OAuthAnswerStream(model=model,token_provider=session.token,client_factory=client_factory)
