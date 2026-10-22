"""Read-only, portable verification of the reviewed 512-point spectrum assets.

Run from any working directory:
    python safevision/tools/check_v3_spectrum_oracle537.py [--repo REPOSITORY]
Or import ``check(repository_root)``; invalid assets raise ValueError.

Requires NumPy. The reviewed vectors were generated with NumPy 2.3.5 and this
checker was tested with that version: ``python -m pip install numpy==2.3.5``.
Other versions are accepted only if they reproduce the same reviewed samples,
rounded FFT components and dominant bins. No RTL FFT algorithm is copied here:
the oracle is numpy.fft.fft, with independently specified signal cases.

The tool writes no files and never regenerates ROMs, testbenches or vectors.
It checks both pinned file hashes (LF/CRLF portable) and mathematical semantics.
The 12-LSB allowance belongs to the separate RTL simulation; stored oracle
components themselves must be the correctly rounded independent FFT results.
This asset check alone is not RTL simulation, timing or hardware acceptance.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
N = 512
RATE = 48000
RTL_COMPONENT_TOLERANCE = 12
ASSETS = "safevision/verification/assets/spectrum539/"
ROM = "safevision/assets/audio/v3_spectrum_twiddle.mem"
CASES = (
    "silence", "dc", "bin1", "bin2", "bin3", "bin5", "bin11", "bin23",
    "bin47", "bin93", "bin167", "bin223", "two_tone", "dc_plus_tone",
    "quiet", "volume20", "noise", "impulse",
)
ALGORITHM = ("Independent numpy.fft.fft of mean-removed, quantized periodic Hann "
             "input; forward normalization1/N; no RTL FFT copied")
# Reviewed file contents, not values supplied by reference.json. Canonical
# hashes normalise CRLF to LF only; no other edit or whitespace is ignored.
PINNED = {
    ROM: "e71d7316644d9d2d17630a8a722c7377d9582f19b124d926c93795350fae12e3",
    ASSETS + "spectrum_samples539.mem": "acf2578149ec00ecb8698127f2f63e995fb78af58272740621532af0f4016015",
    ASSETS + "spectrum_expected539.mem": "3f09e21b62e3fa56712dd1710da9995684c6cba8317c4e3a2eef31bb5117892c",
    ASSETS + "spectrum_peaks539.mem": "216d219ff406dcabde3c2bcb2bf4a2439b58fe53ce7594032cde0cc693cca3d0",
    ASSETS + "reference.json": "f70ef83ffd384ea90f6c846d159d80690724c05054f607501b8f85ded2d8f4eb",
}
ROM_COPIES = (
    "safevision/rtl/video/v3_spectrum_twiddle.mem",
    "safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/base/v3_spectrum_twiddle.mem",
    "safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/hd/v3_spectrum_twiddle.mem",
)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def _payload(root, name, expected_hash, fingerprints):
    raw = (root / name).read_bytes()
    canonical = raw.replace(b"\r\n", b"\n")
    require(b"\r" not in canonical, "unsupported line ending: " + name)
    digest = hashlib.sha256(canonical).hexdigest()
    require(digest == expected_hash, "reviewed file hash mismatch: " + name)
    fingerprints[name] = {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "canonical_lf_sha256": digest,
        "bytes": len(raw),
    }
    return canonical.decode("ascii")


def _words(text, count, digits, name):
    tokens = text.split()
    require(len(tokens) == count, "wrong word count: " + name)
    require(all(re.fullmatch(r"[0-9A-Fa-f]{" + str(digits) + r"}", t)
                for t in tokens), "invalid word width/encoding: " + name)
    return [int(t, 16) for t in tokens]


def _signals(np):
    phase = 2 * np.pi * np.arange(N) / N
    tone = lambda k, amplitude: np.rint(amplitude * np.sin(phase * k)).astype(np.int64)
    signals = [np.zeros(N, dtype=np.int64), np.full(N, 19000, dtype=np.int64)]
    signals.extend(tone(k, 20000) for k in (1, 2, 3, 5, 11, 23, 47, 93, 167, 223))
    signals.extend((tone(5, 10000) + tone(100, 16000), tone(23, 5000) + 10000,
                    tone(23, 700), tone(23, 140),
                    np.random.Generator(np.random.PCG64(539)).integers(
                        -32768, 32768, N, dtype=np.int64),
                    np.concatenate((np.array([32767], dtype=np.int64),
                                    np.zeros(N - 1, dtype=np.int64)))))
    return phase, signals


def check(root=ROOT):
    """Return accepted evidence after checking every reviewed asset value.

    Raises ValueError/OSError on corruption; raises RuntimeError when NumPy is
    unavailable. Does not trust reference.json to define cases or tolerances.
    """
    try:
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("NumPy is required; install numpy==2.3.5") from exc
    root = Path(root).resolve()
    fingerprints = {}
    contents = {name: _payload(root, name, digest, fingerprints)
                for name, digest in PINNED.items()}
    for name in ROM_COPIES:
        copy = _payload(root, name, PINNED[ROM], fingerprints)
        require(copy == contents[ROM], "quarter ROM copy differs: " + name)

    metadata = json.loads(contents[ASSETS + "reference.json"])
    expected_metadata = dict(numpy="2.3.5", algorithm=ALGORITHM, points=N,
                             sample_rate=RATE, cases=list(CASES),
                             component_tolerance=RTL_COMPONENT_TOLERANCE)
    require(metadata == expected_metadata, "unreviewed spectrum metadata/cases/tolerance")
    coefficients = _words(contents[ROM], 512, 4, ROM)
    samples = _words(contents[ASSETS + "spectrum_samples539.mem"], 18 * N, 4, "samples")
    packed = _words(contents[ASSETS + "spectrum_expected539.mem"], 18 * N, 9, "FFT components")
    peaks = _words(contents[ASSETS + "spectrum_peaks539.mem"], 18, 3, "dominant bins")

    phase, signals = _signals(np)
    require(len(signals) == len(CASES) == 18, "independent case inventory is incomplete")
    independent_quarter = np.rint(32767 * np.sin(phase[:128])).astype(np.int64)
    require(coefficients[:128] == independent_quarter.tolist(), "quarter-wave coefficients differ from sine")
    require(not any(coefficients[128:]), "quarter-wave zero padding corrupted")
    cosines = np.rint(32767 * np.cos(phase)).astype(np.int64)
    sines = np.rint(-32767 * np.sin(phase)).astype(np.int64)
    # Check all 256 complete complex coefficients reconstructed by symmetry,
    # including exact zero/one endpoints, against independent trig evaluation.
    for k in range(256):
        sine = 32767 if k == 128 else coefficients[(-k if k & 128 else k) & 127]
        cosine = 32767 if k == 0 else coefficients[(k if k & 128 else -k) & 127]
        cosine = -cosine if k & 128 else cosine
        require(cosine == int(cosines[k]) and -sine == int(sines[k]),
                "quarter-wave reconstruction mismatch at bin " + str(k))

    reports = []
    window = (32767 - cosines) // 2
    maximum_rounding_error = 0.0
    for case, (name, signal) in enumerate(zip(CASES, signals)):
        require(len(signal) == N and int(signal.min()) >= -32768 and
                int(signal.max()) <= 32767, "invalid independently defined case: " + name)
        observed = samples[case * N:(case + 1) * N]
        require(observed == [int(v) & 0xffff for v in signal],
                "sample semantics mismatch: " + name)
        mean = int(signal.sum()) // N
        quantized_windowed = ((signal - mean) * window) // 32768
        transform = np.fft.fft(quantized_windowed) / N
        real = np.rint(transform.real).astype(np.int64)
        imag = np.rint(transform.imag).astype(np.int64)
        require(bool(np.all(real >= -131072) and np.all(real <= 131071) and
                     np.all(imag >= -131072) and np.all(imag <= 131071)),
                "oracle component exceeds signed18 width: " + name)
        expected = [((int(r) & 0x3ffff) << 18) | (int(i) & 0x3ffff)
                    for r, i in zip(real, imag)]
        require(packed[case * N:(case + 1) * N] == expected,
                "independent NumPy FFT component mismatch: " + name)
        rounding = float(max(np.max(np.abs(real - transform.real)),
                             np.max(np.abs(imag - transform.imag))))
        require(rounding <= 0.50000001, "oracle rounding accuracy exceeded: " + name)
        maximum_rounding_error = max(maximum_rounding_error, rounding)
        re_abs = np.abs(transform[1:256].real)
        im_abs = np.abs(transform[1:256].imag)
        magnitude = np.maximum(re_abs, im_abs) + 0.5 * np.minimum(re_abs, im_abs)
        dominant = 0 if float(magnitude.max()) < 0.1 else int(magnitude.argmax()) + 1
        require(peaks[case] == dominant, "independent dominant-bin mismatch: " + name)
        reports.append(dict(case=name, samples=N, complex_bins=N,
                            dc_mean=mean, dominant_bin=dominant,
                            max_component_rounding_error=rounding))

    return dict(accepted=True, numpy_runtime=np.__version__, numpy_reviewed="2.3.5",
                points=N, sample_rate=RATE, fixed_cases=list(CASES),
                sample_words_compared=18 * N, complex_components_compared=18 * N * 2,
                dominant_bins_compared=18, quarter_coefficients_compared=128,
                reconstructed_complex_coefficients_compared=256,
                zero_padding_words_compared=384,
                rtl_component_tolerance=RTL_COMPONENT_TOLERANCE,
                oracle_component_rounding_error_max=maximum_rounding_error,
                files=fingerprints, cases=reports,
                scope="Read-only independent asset verification; RTL simulation, timing and hardware require separate evidence.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = check(args.repo)
    except Exception as exc:
        print(json.dumps(dict(accepted=False, error=str(exc)), indent=2))
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
