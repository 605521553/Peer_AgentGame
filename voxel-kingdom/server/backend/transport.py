"""Version 2 wire representation; canonical database models remain unchanged."""
from functools import lru_cache
import json
from .models import model_for_ai


@lru_cache(maxsize=128)
def _compact(serialized):
    model = json.loads(serialized)
    boxes = {**model_for_ai(model), **{k: model[k] for k in ('id', 'voxel_count', 'face_count')}}
    return boxes if len(json.dumps(boxes, separators=(',', ':'))) < len(serialized) else model


def compact(model):
    return _compact(json.dumps(model, separators=(',', ':')))


def receipt_for_wire(receipt):
    return {k: v for k, v in receipt.items() if k != 'event'} if receipt else receipt


def chat_for_wire(result):
    return {**result, 'receipt': receipt_for_wire(result.get('receipt'))} if 'receipt' in result else result


def event_for_wire(event, known):
    item = {k: v for k, v in event.items() if k not in ('asset', 'voxel_patch')}
    patch = event.get('voxel_patch')
    if patch and patch['base_blueprint_id'] in known:
        item['voxel_patch'] = patch
    elif 'asset' in event and event['asset']['id'] not in known:
        item['asset'] = compact(event['asset'])
    return item
