
set_param rtl min_control_set 2
set_param rtl min_ripple_len 16
set_param rtl infer_fsm off
set_param gate map_mode area_prior
set_param gate pack_effort high
set_param place effort high
set_param place post_place_opt ultra
set_param place hfn_opt_effort high
set_param route effort routability
set_param route timing on
set_param route fix_hold on

set_param place pr_strategy 2


set_param gate bdd_opt on
set_param gate lut4_map off


set_param route post_route_opt auto
