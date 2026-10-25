"""Explicit offline wiring fixture. Its card changes are not model-quality evidence."""
import json


class SyntheticLearningCompletion:
    def __init__(self, log=None):
        self.calls=0
        self.log=log

    async def __call__(self,prompt,instructions,**_):
        self.calls+=1
        value=json.loads(prompt);learning=value.get('learning_memory') or {}
        adjustments=learning.get('adjustments',[])
        text=value['current_request'].lower()
        semantic=value.get('semantic_request','').lower()
        coding='function' in text or 'code' in text or 'function' in semantic or 'code' in semantic
        if coding:
            lead='Check the input contract, then explain the empty-list case before returning the first item.'
            points=['Use an explicit guard for an empty list.','Keep the original item order.']
            detail={'kind':'code','language':'python','text':'def first_or_none(items):\n    return items[0] if items else None\n'}
            if 'concise_lead' in adjustments:
                lead='Check the empty list before returning its first item.';points=['Return None when the list is empty.']
            elif 'stepwise' in adjustments:
                lead='Check the empty case first, then return the first item.';points=['Keep the original item order.']
        else:
            lead='Discuss queue capacity and rejection before choosing an overload policy.'
            points=['Keep capacity bounded and make rejection explicit.','Discuss cancellation and retry conditions.'];detail=None
            if 'concise_lead' in adjustments:
                lead='Use a bounded queue and reject overload explicitly.';points=['Keep cancellation and retry policy explicit.']
            elif 'stepwise' in adjustments:
                lead='Explain capacity first, then define rejection and cancellation.';points=['Keep the steps separate from personal experience.']
        if self.log is not None:
            self.log.write(json.dumps({'kind':'synthetic_model_completed','call':self.calls,'hasLearning':bool(learning),
                                      'adjustments':adjustments,'sourceCount':len(learning.get('supportIDs',[]))},separators=(',',':'))+'\n')
            self.log.flush()
        return json.dumps({'lead':lead,'points':points,'detail':detail,'assumptions':[],
                           'coverage':['current_request'],'personal_fact_ids':[]})


def main():
    import argparse
    from pathlib import Path
    import runpy
    import sys
    arguments=sys.argv[1:]
    if '-m' not in arguments:return 2
    boundary=arguments.index('-m')
    parser=argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--synthetic-learning-test',action='store_true',required=True)
    parser.add_argument('--log',required=True)
    options=parser.parse_args(arguments[:boundary])
    runtime=arguments[boundary:]
    if runtime[:2]!=['-m','relay_spike.session_host'] or '--fixture-model' not in runtime:return 2
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
    from tests.support.visual_backend_helper import _open_log
    import relay_spike.session_host as host_module
    original=host_module.SessionHost
    try:
        with _open_log(options.log) as log:
            class SyntheticHost(original):
                def __init__(self,**values):
                    values['complete']=SyntheticLearningCompletion(log)
                    super().__init__(**values)
            host_module.SessionHost=SyntheticHost
            # Use the actual framed loop, native request/retirement gates and
            # one-answer coordinator. Only the external completion is fictional.
            sys.argv=['relay_spike.session_host',*runtime[2:]]
            host_module.main()
            return 0
    finally:
        host_module.SessionHost=original


if __name__=='__main__':raise SystemExit(main())
