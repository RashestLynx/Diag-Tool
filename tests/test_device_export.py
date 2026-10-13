import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import device_export as dx  # noqa: E402


class AppleLookupTests(unittest.TestCase):
    def test_product_type_to_model_and_soc(self):
        self.assertEqual(dx.apple_model_lookup("iPhone14,5"), ("iPhone 13", "Apple A15 Bionic"))
        self.assertEqual(dx.apple_model_lookup("iPhone16,1"), ("iPhone 15 Pro", "Apple A17 Pro"))

    def test_unknown_product_type(self):
        self.assertIsNone(dx.apple_model_lookup("iPhone99,9"))


class AppleSerialDateTests(unittest.TestCase):
    def test_new_format_is_not_derivable(self):
        # 10-char randomized-era serials carry no date.
        self.assertIn("not derivable", dx.apple_serial_date("ABCDE12345"))

    def test_legacy_format_mentions_a_year(self):
        msg = dx.apple_serial_date("C39XY1234567")
        self.assertIn("2018", msg)
        self.assertIn("checkcoverage.apple.com", msg)


class LuhnTests(unittest.TestCase):
    def test_valid_and_invalid(self):
        self.assertTrue(dx._luhn_is_valid("490154203237518"))
        self.assertFalse(dx._luhn_is_valid("490154203237519"))

    def test_non_digits(self):
        self.assertFalse(dx._luhn_is_valid("49015420x237518"))


class ServiceCallImeiTests(unittest.TestCase):
    def test_decodes_utf16_hex_words(self):
        # Build the "service call" style output for IMEI "123456789012345":
        # each 8-hex word holds two UTF-16 code units, low half first.
        imei = "123456789012345"
        tokens = []
        for i in range(0, len(imei) - 1, 2):
            lo = ord(imei[i])
            hi = ord(imei[i + 1])
            tokens.append(f"{hi:04x}{lo:04x}")
        tokens.append(f"0000{ord(imei[-1]):04x}")  # trailing odd digit
        # Surround with other text to mimic real output; keep tokens space-separated.
        raw = "Result: Parcel ( " + " ".join(tokens) + " )"
        self.assertEqual(dx._parse_service_call_imei(raw), imei)


class DtcTests(unittest.TestCase):
    def test_prefix_decoding(self):
        self.assertEqual(dx._decode_dtc_prefix("P0300"), "Powertrain")
        self.assertEqual(dx._decode_dtc_prefix("C1234"), "Chassis")
        self.assertEqual(dx._decode_dtc_prefix("U0100"), "Network")

    def test_known_code_has_a_fix(self):
        self.assertIn("P0420", dx.DTC_FIXES)
        meaning, fix = dx.DTC_FIXES["P0420"]
        self.assertTrue(meaning and fix)

    def test_describe_any_wellformed_code(self):
        # A code not in the table still gets a structural explanation.
        self.assertNotIn("P1345", dx.DTC_FIXES)
        desc = dx.describe_dtc("P1345")
        self.assertIn("Powertrain", desc)
        self.assertIn("manufacturer-specific", desc)  # second digit 1
        self.assertIn("ignition", desc)  # subsystem digit 3

    def test_describe_generic_vs_bad(self):
        self.assertIn("generic", dx.describe_dtc("P0420"))
        self.assertIn("Network", dx.describe_dtc("U0100"))
        self.assertIn("Not a standard", dx.describe_dtc("hello"))


class AppReferenceJsonTests(unittest.TestCase):
    def test_reference_json_is_up_to_date(self):
        import json
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "app", "assets", "reference.json"), encoding="utf-8") as fh:
            on_disk = json.load(fh)
        self.assertEqual(on_disk, json.loads(json.dumps(dx.reference_as_dict())),
                         "run `python diag_tool.py export-json` to refresh the app's copy")


class ObdGraphTests(unittest.TestCase):
    def test_render_html_has_a_chart_per_numeric_column(self):
        headers = ["elapsed_s", "RPM", "COOLANT_TEMP", "LABEL"]
        rows = [[0, 800, 60, "a"], [1, 1500, 72, "b"], [2, 2200, 85, "c"]]
        html = dx.render_obd_html(headers, rows)
        # RPM and COOLANT_TEMP are numeric -> 2 charts; LABEL is text -> skipped.
        self.assertEqual(html.count("<polyline"), 2)
        self.assertIn("RPM", html)
        self.assertIn("COOLANT_TEMP", html)
        self.assertIn("<!doctype html>", html)

    def test_render_html_handles_missing_values(self):
        headers = ["elapsed_s", "O2"]
        rows = [[0, ""], [1, 0.45], [2, 0.9]]  # one blank cell
        html = dx.render_obd_html(headers, rows)
        self.assertIn("O2", html)  # still charts the column it can

    def test_svg_points_scale_within_viewbox(self):
        svg = dx._svg_line_chart("x", [0, 1, 2], [10, 20, 30], width=100, height=100)
        self.assertIn("<polyline", svg)
        self.assertIn("points=", svg)


class AnalyzeObdTests(unittest.TestCase):
    def titles(self, findings):
        return " | ".join(f["title"] for f in findings)

    def test_lean_fuel_trims_flag_vacuum_leak(self):
        f = dx.analyze_obd({"SHORT_FUEL_TRIM_1": 8, "LONG_FUEL_TRIM_1": 12}, [])
        self.assertIn("lean", self.titles(f).lower())
        self.assertTrue(any("vacuum" in x["cause"].lower() for x in f))

    def test_rich_fuel_trims(self):
        f = dx.analyze_obd({"SHORT_FUEL_TRIM_1": -6, "LONG_FUEL_TRIM_1": -9}, [])
        self.assertIn("rich", self.titles(f).lower())

    def test_overheating(self):
        f = dx.analyze_obd({"COOLANT_TEMP": 112}, [])
        self.assertIn("hot", self.titles(f).lower())

    def test_low_charging_voltage_when_running(self):
        f = dx.analyze_obd({"CONTROL_MODULE_VOLTAGE": 12.1, "RPM": 900}, [])
        self.assertTrue(any("charging" in x["title"].lower() for x in f))

    def test_misfire_code_maps_to_cylinder(self):
        f = dx.analyze_obd({}, ["P0303"])
        self.assertIn("cylinder 3", self.titles(f).lower())

    def test_catalyst_code(self):
        f = dx.analyze_obd({}, ["P0420"])
        self.assertTrue(any("catalytic" in x["title"].lower() for x in f))

    def test_clean_readings_report_nothing_wrong(self):
        f = dx.analyze_obd({"COOLANT_TEMP": 88, "SHORT_FUEL_TRIM_1": 1,
                            "LONG_FUEL_TRIM_1": -2, "CONTROL_MODULE_VOLTAGE": 14.1,
                            "RPM": 800}, [])
        self.assertEqual(len(f), 1)
        self.assertIn("No obvious fault", f[0]["title"])


class CliOfflineTests(unittest.TestCase):
    def test_apple_model_cli(self):
        self.assertEqual(dx.main(["--apple-model", "iPhone12,1"]), 0)

    def test_apple_serial_date_cli(self):
        self.assertEqual(dx.main(["--apple-serial-date", "C39XY1234567"]), 0)


if __name__ == "__main__":
    unittest.main()
