"""Bounded Responses lifecycle accumulator.

Design reference: OpenAI Python SDK v3.37.0 ResponseStreamState, Apache-2.0,
e8a0fd28bbdc1699c97ff0f602b1af3dd378382d. Independently implemented: no
upstream source copied. Stricter identity/replay/budget/refusal rules apply.
"""
from __future__ import annotations
import json


class ResponseProtocolError(ValueError):
    pass


class ResponseAssembler:
    def __init__(self):
        self.response_id = None
        self.sequence = -1
        self.items = {}
        self.parts = {}
        self.finished = set()
        self.terminal = False
        self.bytes = 0

    def feed(self, event):
        def reject():
            self.terminal = True
            raise ResponseProtocolError('invalid_response_lifecycle')
        if self.terminal or not isinstance(event, dict): reject()
        try: self.bytes += len(json.dumps(event,ensure_ascii=False).encode())
        except (ValueError, UnicodeError): reject()
        seq, typ = event.get('sequence_number'), event.get('type')
        if type(seq) is not int or seq <= self.sequence or self.bytes > 524288: reject()
        self.sequence = seq
        if typ in ('response.failed','response.incomplete','error') or 'refusal' in str(typ): reject()
        response = event.get('response')
        if response is not None:
            if not isinstance(response, dict) or not isinstance(response.get('id'),str): reject()
            if self.response_id is None:
                if typ != 'response.created': reject()
                self.response_id = response['id']
            if response['id'] != self.response_id: reject()
        if self.response_id is None: reject()
        if typ == 'response.created':
            if self.sequence != seq or response.get('status') != 'in_progress' or self.items: reject()
        elif typ == 'response.output_item.added':
            index, item = event.get('output_index'), event.get('item')
            if type(index) is not int or not 0 <= index < 32 or index in self.items or not isinstance(item,dict): reject()
            if not isinstance(item.get('id'),str) or item.get('type') not in ('message','reasoning'): reject()
            self.items[index] = item
        elif typ in ('response.content_part.added','response.output_text.delta','response.output_text.done','response.content_part.done'):
            index, part = event.get('output_index'), event.get('content_index')
            if index not in self.items or event.get('item_id') != self.items[index]['id'] or type(part) is not int or not 0 <= part < 16 or index in self.finished: reject()
            key = (index,part)
            if typ == 'response.content_part.added':
                if key in self.parts or event.get('part',{}).get('type') != 'output_text': reject()
                self.parts[key] = ''
            elif typ == 'response.output_text.delta':
                delta=event.get('delta')
                if key not in self.parts or not isinstance(delta,str): reject()
                self.parts[key] += delta
                if len(self.parts[key].encode()) > 8192: reject()
            elif typ == 'response.output_text.done':
                if key not in self.parts or event.get('text') != self.parts[key]: reject()
            else:
                if key not in self.parts or event.get('part',{}).get('text') != self.parts[key]: reject()
        elif typ == 'response.output_item.done':
            index,item = event.get('output_index'),event.get('item')
            if index not in self.items or index in self.finished or not isinstance(item,dict) or item.get('id') != self.items[index]['id'] or item.get('status') != 'completed': reject()
            if item.get('type') != self.items[index].get('type'): reject()
            content=item.get('content',[])
            if not isinstance(content,list): reject()
            for part in content:
                if not isinstance(part,dict) or part.get('type') not in ('output_text',): reject()
            for (i,p),text in self.parts.items():
                if i == index and (p >= len(content) or content[p].get('text') != text): reject()
            self.items[index] = item
            self.finished.add(index)
        elif typ == 'response.completed':
            if response.get('status') != 'completed' or not self.items or self.finished != set(self.items): reject()
            output=response.get('output')
            if not isinstance(output,list) or output != [self.items[i] for i in sorted(self.items)]: reject()
            result=''.join(part.get('text','') for item in output if item.get('type')=='message' for part in item.get('content',[]))
            if not result or len(result.encode()) > 8192: reject()
            self.terminal=True
            return result
        elif typ not in ('response.in_progress','response.reasoning_summary_part.added','response.reasoning_summary_text.delta','response.reasoning_summary_text.done','response.reasoning_summary_part.done'):
            reject()
        return None

    def finish(self):
        if not self.terminal:
            raise ResponseProtocolError('missing_response_completed')
