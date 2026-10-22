# BASE strategy2: only EG4 parameters confirmed in native registered tables.
set_param place pr_strategy 5

set_param place post_place_opt medium
set_param place hfn_opt_effort low

set_param place seed 1

# Target measured SYS100 watchdog route using documented setup-margin mode.
set_param route timing greedy

# Measured capacity profile; original clocks, I/O and STA gates retained.
set_param rtl min_ripple_len 32

# Measured EG4 packing strategy; clocks and full STA limits stay unchanged.
set_param place opt_timing off
