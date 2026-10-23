"""Strict bounded native/helper framing. No transcript/raw exception diagnostics."""
from __future__ import annotations
import json
import uuid
from .generated_answer import strict_json, CardError
from .native_eou_wire import decode_native_eou_wire, UINT64_MAX

MAX_FRAME=16384
class WireError(ValueError): pass

def encode_frame(value):
    try: data=json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8')
    except (ValueError,TypeError,UnicodeError): raise WireError('invalid_frame') from None
    if not 0<len(data)<=MAX_FRAME: raise WireError('frame_budget')
    return len(data).to_bytes(4,'big')+data

class FrameDecoder:
    def __init__(self): self.buffer=bytearray();self.length=None
    def feed(self,chunk):
        if not isinstance(chunk,bytes) or len(chunk)>MAX_FRAME*2: raise WireError('chunk_budget')
        self.buffer.extend(chunk);out=[]
        while True:
            if self.length is None:
                if len(self.buffer)<4: break
                self.length=int.from_bytes(self.buffer[:4],'big');del self.buffer[:4]
                if not 0<self.length<=MAX_FRAME: raise WireError('frame_budget')
            if len(self.buffer)<self.length: break
            raw=bytes(self.buffer[:self.length]);del self.buffer[:self.length];self.length=None
            try: out.append(strict_json(raw,max_bytes=MAX_FRAME))
            except CardError: raise WireError('invalid_frame') from None
        return tuple(out)
    def finish(self):
        if self.buffer or self.length is not None: raise WireError('truncated_frame')

def u64(v,positive=False):
    if type(v) is not int or not (1 if positive else 0)<=v<=UINT64_MAX: raise WireError('invalid_counter')
    return v

def exact(value,keys):
    if type(value) is not dict or set(value)!=set(keys): raise WireError('field_set')
    return value

def uuid_string(value):
    try:
        if not isinstance(value,str) or str(uuid.UUID(value))!=value.lower(): raise ValueError()
    except ValueError: raise WireError('invalid_uuid') from None
    return value.lower()

OUTER=('schemaVersion','captureSessionID','sessionEpoch','eventSequence','presentationGeneration','kind','sourceCode','streamGeneration','emittedUptimeNanoseconds','payload','requestID')
REASONS=frozenset(('user_stop','consent_revoked','selected_app_unavailable','capture_error','device_changed','sequence_gap','queue_overflow','model_unavailable','vad_unavailable','asr_unavailable','clock_invalid','transport_closed','shutdown_timeout'))

def decode_event(value):
    exact(value,OUTER)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1: raise WireError('schema_version')
    uuid_string(value['captureSessionID'])
    for key in ('sessionEpoch','eventSequence','presentationGeneration'): u64(value[key],True)
    u64(value['emittedUptimeNanoseconds'])
    kind,source,p=value['kind'],value['sourceCode'],value['payload']
    if kind in ('speech_started','speech_ended','eou'):
        if type(source) is not int or source not in (1,2): raise WireError('invalid_source')
        u64(value['streamGeneration'])
    elif kind in ('source_unavailable','discontinuity'):
        if type(source) is not int or source not in (1,2): raise WireError('invalid_source')
        u64(value['streamGeneration'])
    elif kind in ('session_started','stopping','stopped'):
        if source is not None or value['streamGeneration'] is not None: raise WireError('control_source')
    else: raise WireError('event_kind')
    if kind=='eou' and source==2: uuid_string(value['requestID'])
    elif value['requestID'] is not None: raise WireError('request_scope')
    if kind=='session_started':
        exact(p,('selectedBundleID','microphoneEnabled'))
        if not isinstance(p['selectedBundleID'],str) or not 0<len(p['selectedBundleID'].encode())<=255 or type(p['microphoneEnabled']) is not bool: raise WireError('session_config')
    elif kind=='speech_started':
        exact(p,('activityID','startHostTime','detectedUptimeNanoseconds','timebase'))
        for key in ('activityID','startHostTime','detectedUptimeNanoseconds'): u64(p[key])
        validate_timebase(p['timebase'])
    elif kind=='speech_ended':
        exact(p,('activityID','endHostTime','lastSpeechInputSequence','timebase'))
        for key in ('activityID','endHostTime','lastSpeechInputSequence'): u64(p[key])
        validate_timebase(p['timebase'])
    elif kind=='eou':
        exact(p,('event','activityID','firstInputSequence','lastInputSequence','activityClosed','lastSpeechInputSequence'))
        for key in ('activityID','firstInputSequence','lastInputSequence','lastSpeechInputSequence'): u64(p[key])
        if type(p['activityClosed']) is not bool: raise WireError('activity_closed')
        inner=decode_native_eou_wire(json.dumps(p['event'],separators=(',',':')).encode())
        if p['event']['sourceCode']!=source or inner.stream_generation!=value['streamGeneration']: raise WireError('source_mismatch')
        return value,inner
    else:
        exact(p,('reason',))
        if p['reason'] not in REASONS: raise WireError('control_reason')
    return value,None

def validate_timebase(tb):
    exact(tb,('hostTicksAtAnchor','uptimeNsAtAnchor','nsNumer','nsDenom'))
    for key in tb: u64(tb[key],key in ('nsNumer','nsDenom'))

def host_ms(ticks,tb):
    value=tb['uptimeNsAtAnchor']+(ticks-tb['hostTicksAtAnchor'])*tb['nsNumer']//tb['nsDenom']
    return u64(value)//1000000
