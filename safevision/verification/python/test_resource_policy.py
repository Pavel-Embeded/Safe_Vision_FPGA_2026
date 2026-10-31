import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'safevision/tools'))

from check_v3_board import resource_gate
from v3_resource_policy import CAPACITY, load, validate


class ResourcePolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = load(ROOT)

    def report(self, **changes):
        values = {'lut': 19600, 'reg': 15680, 'bram': 40, 'bram32k': 6, 'dsp': 29, 'pll': 3}
        values.update(changes)
        return '\n'.join(f'#{key} {values[key]} out of {capacity} {100 * values[key] / capacity:.2f}%'
                         for key, capacity in CAPACITY.items())

    def test_capacity_boundary(self):
        self.assertTrue(resource_gate(self.report(), self.policy)['accepted'])
        for changes in ({'lut': 19601}, {'reg': 15681}, {'bram': 41}, {'bram32k': 7},
                        {'dsp': 30}, {'pll': 4}, {'pll': 2}):
            with self.subTest(changes=changes):
                self.assertFalse(resource_gate(self.report(**changes), self.policy)['accepted'])

    def test_reject_policy_relaxation(self):
        changes = [
            ('physical_capacity', {**CAPACITY, 'lut': 30000}),
            ('hard_caps_percent', {'lut': 100, 'reg': 100, 'ram': 100}),
            ('targets_percent', {'lut': 100, 'reg': 100, 'ram': 100}),
            ('ram32k_cost_in_9k_tiles', 1),
            ('requires_successful_native_placement_routing', False),
            ('requires_all_corner_setup_hold_recovery_removal', False),
            ('feature_reduction_permitted', True),
        ]
        for field, value in changes:
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                policy[field] = value
                with self.assertRaises(ValueError):
                    validate(policy)

    def test_reject_schema_and_requirement_corruption(self):
        for field, value in [('schema', 1), ('schema', 2.0), ('revision', True),
                             ('revision', 1), ('policy_id', 'other'), ('device', 'other'),
                             ('requirements', {}), ('requires_successful_native_placement_routing', 1),
                             ('feature_reduction_permitted', 0), ('ram32k_cost_in_9k_tiles', 4.0)]:
            with self.subTest(field=field, value=value):
                policy = copy.deepcopy(self.policy)
                policy[field] = value
                with self.assertRaises(ValueError):
                    validate(policy)
        for policy in (None, [], {**self.policy, 'extra': True}):
            with self.subTest(policy=policy):
                with self.assertRaises(ValueError):
                    validate(policy)
        for field in self.policy:
            with self.subTest(missing=field):
                policy = copy.deepcopy(self.policy)
                del policy[field]
                with self.assertRaises(ValueError):
                    validate(policy)

    def test_reject_noninteger_budget_values(self):
        for field in ('physical_capacity', 'hard_caps_percent', 'targets_percent'):
            with self.subTest(field=field):
                policy = copy.deepcopy(self.policy)
                key = next(iter(policy[field]))
                policy[field][key] = float(policy[field][key])
                with self.assertRaises(ValueError):
                    validate(policy)

    def test_reject_report_capacity_spoofing_and_missing_resources(self):
        spoofed = self.report().replace('out of 19600', 'out of 30000')
        self.assertFalse(resource_gate(spoofed, self.policy)['accepted'])
        with self.assertRaises(ValueError):
            resource_gate('\n'.join(self.report().splitlines()[:-1]), self.policy)
        with self.assertRaises(ValueError):
            resource_gate(self.report() + '\n' + self.report(), self.policy)


if __name__ == '__main__':
    unittest.main()
