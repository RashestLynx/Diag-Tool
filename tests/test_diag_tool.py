import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import diag_tool  # noqa: E402
from diag_tool import SYMPTOM_BY_KEY, causes_for, detect_device, detect_symptoms  # noqa: E402


class DetectDeviceTests(unittest.TestCase):
    def test_common_devices(self):
        self.assertEqual(detect_device("My iPhone won't charge"), "phone")
        self.assertEqual(detect_device("macbook is overheating"), "laptop")
        self.assertEqual(detect_device("PS5 controller has stick drift"), "console")
        self.assertEqual(detect_device("AirPods only play in one ear"), "headphones")
        self.assertEqual(detect_device("the router keeps dropping"), "router")

    def test_longest_keyword_wins(self):
        self.assertEqual(detect_device("galaxy tab screen flickers"), "tablet")

    def test_whole_word_only(self):
        self.assertIsNone(detect_device("pcie errors"))

    def test_unknown(self):
        self.assertIsNone(detect_device("it is broken"))


class DetectSymptomTests(unittest.TestCase):
    def keys(self, text):
        return [s.key for s in detect_symptoms(text)]

    def test_multiple_symptoms(self):
        keys = self.keys("my phone won't charge and gets hot")
        self.assertIn("not_charging", keys)
        self.assertIn("overheating", keys)

    def test_curly_apostrophe(self):
        self.assertIn("no_power", self.keys("laptop won’t turn on"))

    def test_water(self):
        self.assertIn("water", self.keys("dropped it in the toilet"))

    def test_nothing(self):
        self.assertEqual(self.keys("blah"), [])


class CausesTests(unittest.TestCase):
    def test_sorted_by_likelihood(self):
        causes = causes_for(SYMPTOM_BY_KEY["slow"], None)
        self.assertEqual([c.likelihood for c in causes],
                         sorted((c.likelihood for c in causes), reverse=True))

    def test_device_filter(self):
        names = [c.name for c in causes_for(SYMPTOM_BY_KEY["no_power"], "router")]
        self.assertNotIn("Battery fully drained", names)
        self.assertIn("Failed power supply (PSU)", names)

    def test_every_symptom_has_causes_for_its_devices(self):
        for s in diag_tool.SYMPTOMS:
            for device in (s.devices or diag_tool.DEVICES):
                self.assertTrue(causes_for(s, device), f"{s.key} has no causes for {device}")


class CliTests(unittest.TestCase):
    def test_diagnose(self):
        self.assertEqual(diag_tool.main(["diagnose", "laptop", "is", "slow"]), 0)

    def test_diagnose_unknown(self):
        self.assertEqual(diag_tool.main(["diagnose", "blah"]), 1)

    def test_identify(self):
        self.assertEqual(diag_tool.main(["identify", "--imei", "490154203237518"]), 0)
        self.assertEqual(diag_tool.main(["identify", "--imei", "490154203237519"]), 1)

    def test_scan_runs(self):
        self.assertIn(diag_tool.main(["scan"]), (0, 1))
        self.assertTrue(diag_tool.identify_host()["kind"])


class AppKnowledgeTests(unittest.TestCase):
    def test_app_json_is_up_to_date(self):
        import json
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "app", "assets", "knowledge.json"), encoding="utf-8") as fh:
            on_disk = json.load(fh)
        self.assertEqual(on_disk, json.loads(json.dumps(diag_tool.knowledge_as_dict())),
                         "run `python diag_tool.py export-json` to refresh the app's copy")


if __name__ == "__main__":
    unittest.main()
