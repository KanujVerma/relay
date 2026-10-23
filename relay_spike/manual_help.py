"""Strict explicit task request. This never decodes or fabricates an audio event."""
from .panel_wire import exact,u64,uuid_string,WireError
from .generated_answer import bounded_text,CardError

_FIELDS=('schemaVersion','kind','captureSessionID','sessionEpoch','presentationGeneration','requestID',
    'anchorEventSequence','emittedUptimeNanoseconds','question')

def decode_manual_help(value):
    exact(value,_FIELDS)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='manual_help_request':raise WireError('manual_schema')
    uuid_string(value['captureSessionID']);uuid_string(value['requestID'])
    for key in ('sessionEpoch','presentationGeneration','anchorEventSequence','emittedUptimeNanoseconds'):u64(value[key],True)
    try:bounded_text(value['question'],500)
    except (CardError,TypeError):raise WireError('manual_question') from None
    native=dict(value);native['eventSequence']=value['anchorEventSequence']
    return native
