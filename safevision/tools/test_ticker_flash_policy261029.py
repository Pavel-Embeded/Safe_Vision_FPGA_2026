"""Keep the short installation profile explicit and refuse broader claims."""
import copy,unittest
from verify_ticker_flash_delivery261029 import policy_check

class PolicyControls(unittest.TestCase):
    def setUp(self):
        self.policy=dict(schema=1,profile='flash_install261029',minimum_continuous_monitor_seconds=60,manual_transitions=100,recoveries=10,two_hour_test_required=False,two_hour_pass_claimed=False,change_authorized_by='user',user_verbatim='不用两个小时的检测了')
    def test_authorized_profile(self):self.assertEqual(policy_check(self.policy)['minimum_continuous_monitor_seconds'],60)
    def test_missing_user_instruction(self):
        self.policy['user_verbatim']=''
        with self.assertRaisesRegex(ValueError,'user instruction'):policy_check(self.policy)
    def test_duration_not_reduced_further(self):
        self.policy['minimum_continuous_monitor_seconds']=1
        with self.assertRaisesRegex(ValueError,'limits'):policy_check(self.policy)
    def test_transition_and_recovery_counts_retained(self):
        for name in('manual_transitions','recoveries'):
            altered=copy.deepcopy(self.policy);altered[name]=0
            with self.assertRaisesRegex(ValueError,'limits'):policy_check(altered)
    def test_two_hour_claim_refused(self):
        self.policy['two_hour_pass_claimed']=True
        with self.assertRaisesRegex(ValueError,'two-hour'):policy_check(self.policy)
    def test_unknown_profile_refused(self):
        self.policy['profile']='other'
        with self.assertRaisesRegex(ValueError,'Unknown'):policy_check(self.policy)

if __name__=='__main__':unittest.main()
