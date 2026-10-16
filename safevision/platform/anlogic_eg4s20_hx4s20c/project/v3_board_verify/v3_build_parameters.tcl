# Reviewed common native parameters; GUI and CLI resolve this same file.
set_param rtl min_control_set 3
set_param rtl min_ripple_len 16
set_param rtl infer_fsm off
set_param gate map_mode area_prior
set_param gate pack_effort high
set_param place effort high
set_param place post_place_opt high
set_param route effort routability
set_param route timing on
set_param route fix_hold on
