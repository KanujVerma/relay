"""Owned POSIX storage mechanics shared with the reviewed OAuth spike.

No paths, IO or secrets are loaded at import. This module never encrypts data;
the product caller must supply ciphertext. Lockfiles are never unlinked.
"""
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import stat
import sys
import tempfile

class ProtectedStorageError(RuntimeError):pass

def durable_sync(fd):
    """Require the strongest supported Mac flush, without a power-loss claim."""
    if sys.platform=='darwin':
        command=getattr(fcntl,'F_FULLFSYNC',None)
        if command is None:raise ProtectedStorageError('Strong macOS credential sync is unavailable on this runtime.')
        try:fcntl.fcntl(fd,command)
        except OSError:raise ProtectedStorageError('Strong macOS credential sync is unsupported on this filesystem.') from None
    else:os.fsync(fd)

def directory(path,*,create=False):
    path=Path(path)
    try:
        if create:path.mkdir(mode=0o700,parents=True,exist_ok=True)
        info=path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o700:
            raise ProtectedStorageError('Credential directory must be an owner-only directory.')
    except OSError:raise ProtectedStorageError('Credential directory is unavailable.') from None

def _file(info,limit):
    if (not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_nlink!=1
        or stat.S_IMODE(info.st_mode)!=0o600 or info.st_size>limit):
        raise ProtectedStorageError('Credential file must be an owner-only bounded regular file.')

def read_bytes(path,*,limit):
    path=Path(path);directory(path.parent)
    try:
        fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
        try:
            _file(os.fstat(fd),limit)
            result=bytearray()
            while len(result)<=limit:
                chunk=os.read(fd,min(65536,limit+1-len(result)))
                if not chunk:break
                result.extend(chunk)
            if not result or len(result)>limit:raise ProtectedStorageError('Credential file budget is invalid.')
            return bytes(result)
        finally:os.close(fd)
    except OSError:raise ProtectedStorageError('Credential file is unavailable.') from None

def sync_parent(path,*,sync=None):
    """Sync post-replacement directory metadata; unsupported sync is failure."""
    sync=sync or durable_sync
    if not hasattr(os,'O_NOFOLLOW'):raise ProtectedStorageError('Secure credential-directory sync needs POSIX no-follow.')
    try:
        fd=os.open(Path(path).parent,os.O_RDONLY|os.O_NOFOLLOW|getattr(os,'O_DIRECTORY',0))
        try:
            if not stat.S_ISDIR(os.fstat(fd).st_mode):raise ProtectedStorageError('Credential parent is not a directory.')
            sync(fd)
        finally:os.close(fd)
    except OSError:raise ProtectedStorageError('Could not durably sync credential rotation on this filesystem.') from None

def replace_bytes(path,data,*,sync=None,sync_directory=None):
    path=Path(path);directory(path.parent,create=True)
    sync=sync or durable_sync;sync_directory=sync_directory or sync_parent
    try:
        try:_file(path.lstat(),2**31)
        except FileNotFoundError:pass
        fd,temporary=tempfile.mkstemp(dir=path.parent,prefix='.relay-',text=False)
        try:
            os.fchmod(fd,0o600)
            with os.fdopen(fd,'wb') as output:
                output.write(data);output.flush();sync(output.fileno())
            os.replace(temporary,path);sync_directory(path)
        finally:
            if os.path.exists(temporary):os.unlink(temporary)
    except OSError:raise ProtectedStorageError('Could not durably replace credentials.') from None

@contextmanager
def credential_lock(path,*,nonblocking=False):
    path=Path(path);directory(path.parent,create=True)
    if not hasattr(os,'O_NOFOLLOW'):raise ProtectedStorageError('Secure refresh lock requires POSIX no-follow support.')
    try:fd=os.open(path.parent/(path.name+'.lock'),os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    except OSError:raise ProtectedStorageError('Could not securely open the OAuth refresh lock.') from None
    try:
        _file(os.fstat(fd),0)
        try:fcntl.flock(fd,fcntl.LOCK_EX|(fcntl.LOCK_NB if nonblocking else 0))
        except OSError:raise ProtectedStorageError('Credential owner is busy.') from None
        try:yield
        finally:fcntl.flock(fd,fcntl.LOCK_UN)
    finally:os.close(fd)
