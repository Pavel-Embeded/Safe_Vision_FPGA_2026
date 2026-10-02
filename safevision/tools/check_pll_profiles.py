"""Audit TD PLL parameters and documented frequency limits; leave vendor RTL intact."""
import json
import re
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
IP_DIR = ROOT / "safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll"
FIN = Fraction(50_000_000)
# DS301 v2.7.6 section 3 refers EG4S20 DC/AC to the EAGLE family.
# DS300 v3.9.4 table 2-14 and tables 3-17/3-18 (pages 37, 98).
INPUT_MIN_HZ, INPUT_MAX_HZ = 10_000_000, 400_000_000
VCO_MIN_HZ, VCO_MAX_HZ = 300_000_000, 1_200_000_000
OUTPUT_MIN_HZ, OUTPUT_MAX_HZ = 4_000_000, 400_000_000
CLOCK_RECOMMENDED_MAX_HZ = 440_000_000


def output_frequency_legal(value):
    return OUTPUT_MIN_HZ <= value <= OUTPUT_MAX_HZ


def profile(name):
    source = (IP_DIR / (name + ".v")).read_text(encoding="utf-8")

    def integer(key):
        match = re.search(r"\." + key + r"\((\d+)\)", source)
        if not match:
            raise ValueError(f"{name}: missing {key}")
        return int(match.group(1))

    if '.FIN("50.000000")' not in source or '.FEEDBK_PATH("CLKC0_EXT")' not in source:
        raise ValueError(f"{name}: unexpected reference or feedback configuration")
    ref, fb, c0, c1 = map(integer, ("REFCLK_DIV", "FBCLK_DIV", "CLKC0_DIV", "CLKC1_DIV"))
    if not all(1 <= divider <= 128 for divider in (ref, fb, c0, c1)):
        raise ValueError(f"{name}: divider outside 1..128")
    pfd = FIN / ref
    vco = FIN * fb * c0 / ref
    if not INPUT_MIN_HZ <= FIN <= INPUT_MAX_HZ or not INPUT_MIN_HZ <= pfd <= INPUT_MAX_HZ:
        raise ValueError(f"{name}: input/PFD outside documented limits")
    if not VCO_MIN_HZ <= vco <= VCO_MAX_HZ:
        raise ValueError(f"{name}: VCO outside documented limits")
    result = {"name": name, "ref_div": ref, "fb_div": fb, "c0_div": c0,
              "c1_div": c1, "pfd_hz": float(pfd), "vco_hz": float(vco)}
    if "video" in name:
        c2 = integer("CLKC2_DIV")
        if not 1 <= c2 <= 128 or c1 != 5 * c2:
            raise ValueError(f"{name}: video outputs do not have exact 5:1 ratio")
        result.update(c2_div=c2, serial_hz=float(vco / c2))
    config = ET.parse(IP_DIR / (name + ".ipc")).getroot()
    expected_fields = {"GeneralConfig/Device": "EG4S20BG256",
                       "GeneralConfig/Type": "PLL", "Page1/clk_num": "CLKC0",
                       "Page1/feedback_mode": "Normal", "Page1/enable_reset": "ENABLE",
                       "Page1/pll_lock": "ENABLE", "Page2/bandwidth_setting": "Medium",
                       "Page3/division_factor": str(ref),
                       "Page3/multiplication_factor": str(fb)}
    for key, expected in expected_fields.items():
        if config.findtext(key) != expected:
            raise ValueError(f"{name}: IPC {key} differs from generated/profile settings")
    input_mhz = config.findtext("Page1/input_frequency", "")
    if not input_mhz.endswith("MHz") or Fraction(input_mhz[:-3]) * 1_000_000 != FIN:
        raise ValueError(f"{name}: IPC reference frequency mismatch")
    config_clocks = config.findall("Page3/clocks/clock")
    expected_dividers = {0: c0, 1: c1}
    if "video" in name:
        expected_dividers[2] = c2
    if {int(clock.findtext("id")) for clock in config_clocks} != set(expected_dividers):
        raise ValueError(f"{name}: IPC enabled outputs mismatch")
    for clock in config_clocks:
        index = int(clock.findtext("id"))
        divider = expected_dividers[index]
        if int(clock.findtext("clock_division_factor")) != divider:
            raise ValueError(f"{name}: IPC C{index} divider mismatch")
        if not output_frequency_legal(vco / divider):
            raise ValueError(f"{name}: enabled C{index} outside documented 4..400 MHz output range")
        recorded = clock.findtext("clock_frequency", "")
        if not recorded.endswith("MHz") or abs(Fraction(recorded[:-3]) * 1_000_000 - vco / divider) > Fraction(1, 100):
            raise ValueError(f"{name}: IPC C{index} frequency mismatch")
        if Fraction(clock.findtext("phase_shift")[:-3]) != 0 or integer(f"CLKC{index}_CPHASE") != divider - 1 or integer(f"CLKC{index}_FPHASE") != 0:
            raise ValueError(f"{name}: IPC/generated phase differs from zero-phase profile")
    result["ipc_matches_generated_parameters"] = True
    result["output_frequency_limit_checks"] = [
        {"output": f"C{index}", "frequency_hz": float(vco / divider),
         "pll_max_margin_hz": float(OUTPUT_MAX_HZ - vco / divider),
         "recommended_clock_max_margin_hz": float(CLOCK_RECOMMENDED_MAX_HZ - vco / divider)}
        for index, divider in sorted(expected_dividers.items())
    ]
    return result, vco / c0, vco / c1


def best_frequency(target, video):
    # Enumerate the full legal integer space. Use exact rational arithmetic.
    # Equal VCOs are deduplicated; their divider factorizations do not affect Fi.
    vcos = set()
    for ref in range(1, 6):  # FIN/ref >= 10 MHz
        for fb in range(1, 129):
            for c0 in range(1, 129):
                value = FIN * fb * c0 / ref
                if VCO_MIN_HZ <= value <= VCO_MAX_HZ and output_frequency_legal(value / c0):
                    vcos.add(value)
    dividers = range(5, 129, 5) if video else range(1, 129)
    best = None
    exact = False
    candidates = 0
    excluded = 0
    for vco in vcos:
        for divider in dividers:
            value = vco / divider
            if not output_frequency_legal(value) or (video and not output_frequency_legal(5 * value)):
                excluded += 1
                continue
            error = abs(value - target)
            candidates += 1
            exact = exact or value == target
            if best is None or error < best[0]:
                best = (error, value)
    return best[0], {"unique_vcos": len(vcos), "candidate_frequencies_checked": candidates,
                     "excluded_by_output_frequency": excluded,
                     "exact_target_possible": exact, "nearest_hz": float(best[1])}


def main():
    results = []
    system, sys_hz, mem_hz = profile("sv_system_pll")
    if sys_hz != 100_000_000 or mem_hz != 125_000_000:
        raise ValueError("system PLL does not generate exact 100/125 MHz")
    system.update(sys_hz=float(sys_hz), mem_hz=float(mem_hz))
    results.append(system)
    for name, target in (("sv_video_vga_pll", 25_175_000),
                         ("sv_video_hd_pll", 74_250_000),
                         ("sv_audio_pll", 12_288_000)):
        result, _, actual = profile(name)
        minimum, search = best_frequency(Fraction(target), "video" in name)
        if abs(actual - target) != minimum:
            raise ValueError(f"{name}: generated frequency is not nearest legal target")
        result.update(target_hz=target, actual_hz=float(actual),
                      actual_fraction_hz=str(actual),
                      offset_ppm=float((actual / target - 1) * 1_000_000), search=search)
        results.append(result)
    print(json.dumps({"result": "PASS",
                      "scope": "integer configuration and documented frequency limits only; excludes physical AC measurements, jitter, PCB and receiver compliance",
                      "frequency_limits": {"source": "DS301 v2.7.6 section 3 -> DS300 v3.9.4 tables 2-14, 3-17, 3-18",
                                           "input_pfd_range_hz": [INPUT_MIN_HZ, INPUT_MAX_HZ],
                                           "vco_range_hz": [VCO_MIN_HZ, VCO_MAX_HZ],
                                           "output_range_hz": [OUTPUT_MIN_HZ, OUTPUT_MAX_HZ],
                                           "family_recommended_clock_max_hz": CLOCK_RECOMMENDED_MAX_HZ},
                      "profiles": results}, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
