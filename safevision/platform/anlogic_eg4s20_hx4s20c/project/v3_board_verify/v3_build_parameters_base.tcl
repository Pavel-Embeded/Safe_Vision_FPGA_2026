# BASE strategy2: only EG4 parameters confirmed in native registered tables.
set_param place pr_strategy 6

set_param place post_place_opt medium
set_param place hfn_opt_effort low

set_param place seed 7

# Routability comparison; actual BASE50 control and all media clocks retained.
set_param route timing off

# Measured capacity profile; original clocks, I/O and STA gates retained.
set_param rtl min_ripple_len 32

# Measured EG4 packing strategy; clocks and full STA limits stay unchanged.
set_param place opt_timing off

# Actual clocks/IO remain exact; optimize timing after congestion closure.
set_param route post_route_opt ultra

# Pack small control sets to reduce physical control/routing pressure.
set_param rtl min_control_set 2

# Values emitted by native strategy5 and confirmed by independent readback.
# Set them explicitly so strategy6 never depends on an earlier tool session.
set_param place ce_weight on
set_param place cn_opt_effort high
set_param place critical_hfn_opt on
set_param place enhanced_beeline_opt 3
