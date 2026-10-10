# A/B multiround release 26101002

Baseline: 27cb1394506337e3366215e1658e5c3b739202cd. See the Chinese report in `docs/A_B多轮验证与修复说明_26101002.md`.

`validation.json`: 168 complete successful simulation logs; 42 expected-failure negative controls kept separately; two strict native TD routed timing gates; final distinct four-file BASE/720p card playback and post-reset frames. Every recorded log is hashed and checked for completion. `diagnostics/` contains superseded failures, never counted as passing product tests.

The two bitstreams and their SHA256 identities are in `releases/ab_multiround_26101002`. No board has been programmed or accepted by this delivery. External electrical timing budgets and encrypted-controller/encoder dynamic behavior are not certified by application models. Native STA does compile the original encrypted IP.
