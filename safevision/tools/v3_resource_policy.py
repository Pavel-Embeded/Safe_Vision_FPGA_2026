"""Auditable user-approved resource policy; device capacities cannot be enlarged."""
import json
from v3_sources import FLOW
CAPACITY={'lut':19600,'reg':19600,'bram':64,'bram32k':16,'dsp':29,'pll':4}
TARGETS={'lut':70,'reg':65,'ram':75}
CAPS={'lut':100,'reg':80,'ram':85}

def validate(policy):
 if policy.get('schema')!=1 or policy.get('device')!='EG4S20BG256':raise ValueError('wrong resource-policy schema/device')
 if policy.get('physical_capacity')!=CAPACITY:raise ValueError('resource policy cannot enlarge/change physical device')
 if policy.get('hard_caps_percent')!=CAPS or policy.get('targets_percent')!=TARGETS:raise ValueError('unapproved resource limit/target')
 for key in ('requires_successful_native_placement_routing','requires_all_corner_setup_hold_recovery_removal'):
  if policy.get(key) is not True:raise ValueError('resource policy cannot waive '+key)
 if policy.get('feature_reduction_permitted') is not False or policy.get('ram32k_cost_in_9k_tiles')!=4:raise ValueError('unapproved feature/RAM policy')
 auth=policy.get('authorization',{})
 if auth.get('date')!='2026-10-16' or not auth.get('instruction') or not auth.get('source'):raise ValueError('missing explicit resource authorization')
 return policy

def load(root):return validate(json.loads((root/FLOW/'resource_policy.json').read_text(encoding='utf-8')))
