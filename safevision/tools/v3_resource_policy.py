
import json

from v3_sources import FLOW

CAPACITY = {'lut': 19600, 'reg': 19600, 'bram': 64, 'bram32k': 16, 'dsp': 29, 'pll': 4}
TARGETS = {'lut': 70, 'reg': 65, 'ram': 75}
CAPS = {'lut': 100, 'reg': 80, 'ram': 100}
POLICY_ID = 'SV-RES-EG4S20'
REVISION = 2
REQUIREMENTS = {
    'capacity': 'SV-RES-001',
    'budget': 'SV-RES-002',
    'native_placement_routing': 'SV-TIM-001',
    'all_corner_timing': 'SV-TIM-002',
    'feature_preservation': 'SV-FUNC-001',
}
FIELDS = {
    'schema', 'policy_id', 'revision', 'device', 'requirements', 'physical_capacity',
    'targets_percent', 'hard_caps_percent', 'requires_successful_native_placement_routing',
    'requires_all_corner_setup_hold_recovery_removal', 'feature_reduction_permitted',
    'ram32k_cost_in_9k_tiles',
}


def integer_table(value, expected):
    return isinstance(value, dict) and value == expected and all(type(x) is int for x in value.values())


def validate(policy):
    if not isinstance(policy, dict) or set(policy) != FIELDS:
        raise ValueError('invalid resource-policy fields')
    if type(policy['schema']) is not int or policy['schema'] != 2:
        raise ValueError('unsupported resource-policy schema')
    if policy['policy_id'] != POLICY_ID or type(policy['revision']) is not int or policy['revision'] != REVISION:
        raise ValueError('unapproved resource-policy revision')
    if policy['device'] != 'EG4S20BG256':
        raise ValueError('wrong resource-policy device')
    if policy['requirements'] != REQUIREMENTS:
        raise ValueError('invalid resource-policy requirement references')
    if not integer_table(policy['physical_capacity'], CAPACITY):
        raise ValueError('resource policy cannot change physical device capacity')
    if not integer_table(policy['hard_caps_percent'], CAPS) or not integer_table(policy['targets_percent'], TARGETS):
        raise ValueError('unapproved resource limit or target')
    for key in ('requires_successful_native_placement_routing', 'requires_all_corner_setup_hold_recovery_removal'):
        if policy[key] is not True:
            raise ValueError('resource policy cannot waive ' + key)
    if policy['feature_reduction_permitted'] is not False:
        raise ValueError('resource policy cannot permit feature reduction')
    if type(policy['ram32k_cost_in_9k_tiles']) is not int or policy['ram32k_cost_in_9k_tiles'] != 4:
        raise ValueError('invalid RAM32K physical tile cost')
    return policy


def load(root):
    return validate(json.loads((root / FLOW / 'resource_policy.json').read_text(encoding='utf-8')))
