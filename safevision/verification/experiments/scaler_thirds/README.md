# Exact thirds scaler candidates: isolated experiments

The production coordinate generator produces only Q8 fractions 0, 85 and 170, even during blanking. For channel values 0..63, its rounded Q8 interpolation is exactly `(2*A+B+1)/3` at fraction85 and `(A+2*B+1)/3` at fraction170. All divisions in this document are integer floor divisions. The general scaler interface remains unchanged in production.

Three experimental implementations retain a default general-fraction branch and enable the restricted branch only with `RASTER_THIRDS=1`:

- `scaler_first.v`: an eight-bit constant `/3`.
- `scaler_network.v`: an explicit two-bit remainder network.
- `scaler_delta.v`: signed rounded-third bitplanes, using `round(2*d/3)=d-round(d/3)`.

The independent test exhausts all64×64 channel pairs on both axes, then checks100,000 four-neighbor vectors, nearest selection, valid bubbles and reset. Each variant completed124,589 exact RGB/valid comparisons with zero errors. Inputs at invalid cycles are also checked. A separate production test, `video_v3_fraction_domain`, verifies2,895,004 complete BASE/HD FIT/HD1:1 scanning cycles and proves the fraction-domain contract.

Run from the repository root with Python and the native XSim2018.3 installation:

```powershell
python safevision/verification/experiments/scaler_thirds/run_experiment.py --variant network --run-dir D:/SafeVisionRuns/thirds_network
```

Use a new ASCII output directory. The wrapper creates an isolated minimal source tree and calls the same strict simulation runner. Functional PASS does not imply adoption or resource improvement.

Controlled native HD synthesis in one unchanged source directory gave21840 LUT/15560 FF/52RAM/29DSP for the original control. `first` gave22724/15568/52/19; `network` gave22095/15558/52/19; `delta` gave22464/15559/52/19. These controls predate the shared filesystem/FIFO integration and must not be represented as the current whole-board result. A separate newer integration control gave19416 LUT and the first candidate18973, demonstrating that global DSP allocation can change the whole-design result. Integration candidates require their own source fingerprints, resource comparison, complete RGB regression and routed timing gate before promotion.

These sources and the candidate manifest are deliberately outside production source lists and required suites. No candidate was promoted when this experiment was archived.
