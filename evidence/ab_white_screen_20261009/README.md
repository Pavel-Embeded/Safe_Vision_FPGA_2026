# 2026-10-09 A/B white-screen repair evidence

Read `docs/verification/AB_WHITE_SCREEN_REPAIR_20261009.md` for the Chinese diagnosis,
scope, final timing margins, tests, and hardware acceptance procedure.

`validation.json` indexes successful tests separately from the deliberate failing
`grant_handshake_expected_failure.log`. That isolated negative control restores
the original board writer grant connection and fails at memory word 89. It is
evidence that the regression detects lost write data, not a successful test.
`sd_card_two_images.log` is the final 50-frame, 15,360,000-active-pixel positive run.

`base.*` and `hd.*` record final strict TD routing and bitstream hashes. Full routed
timing reports and the bitstreams are in the local release package; generated
route databases and proprietary HDMI source are not committed here. Source
manifests use the original build paths and byte hashes. This directory disables
Git newline conversion so the original tool evidence hashes remain reproducible.

`protected_blobs.json` verifies unchanged original Git blobs against `ca85b100`.
New source files and modifications are listed separately. Functional tests use
explicit SDRAM/HDMI interface models; real encrypted IP is used in TD synthesis
and routing. Hardware display acceptance has not been performed.
