set_param rtl min_ripple_len 32
set_param place post_place_opt medium
set_param rtl min_control_set 2

# Fixed HD placement profile; compare the current native reports, not older builds.
# Full routed STA remains mandatory; this does not relax any timing budget.
set_param place pr_strategy 14
set_param place hfn_opt_effort low

set_param place seed 0

# TD6.2 manual9.6: maximize setup routing margin; native query accepted greedy.
set_param route timing off

# TD6.2 user guide printed page283: congestion-first routing.
# Final Slow/Fast setup/hold/recovery/removal are still mandatory.
set_param route effort normal
set_param route post_route_opt ultra
