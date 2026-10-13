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


class AppReferenceJsonTests(unittest.TestCase):
    def test_reference_json_is_up_to_date(self):
        import json
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "app", "assets", "reference.json"), encoding="utf-8") as fh:
            on_disk = json.load(fh)
        self.assertEqual(on_disk, json.loads(json.dumps(dx.reference_as_dict())),
                         "run `python diag_tool.py export-json` to refresh the app's copy")


class CliOfflineTests(unittest.TestCase):
    def test_apple_model_cli(self):
        self.assertEqual(dx.main(["--apple-model", "iPhone12,1"]), 0)

    def test_apple_serial_date_cli(self):
        self.assertEqual(dx.main(["--apple-serial-date", "C39XY1234567"]), 0)


if __name__ == "__main__":
    unittest.main()
