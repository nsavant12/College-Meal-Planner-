import importlib.util
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location("evaluation", Path(__file__).with_name("evaluate-recognition.py"))
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)

class EvaluationTests(unittest.TestCase):
    def row(self, **kwargs):
        return dict(file="a", split="test", expected=["apple"], detected=["apple"], baseline=[], **kwargs)
    def test_metrics(self):
        result = e.labels([self.row(), dict(file="b", expected=["banana"], detected=["apple"])])
        self.assertEqual(result["micro"], dict(tp=1, fp=1, fn=1, precision=.5, recall=.5, f1=.5))
    def test_missing_annotations_not_perfect(self):
        self.assertIsNone(e.counts([self.row()], {}))
        self.assertIsNone(e.localization([self.row()], {}))
    def test_duplicate_boxes_cannot_match_twice(self):
        box = dict(name="apple", score=.9, xywh=[0,0,.2,.2])
        result = e.localization([self.row(boxes=[box,box], detectorStatus="available")], {"a": dict(boxes=[box])})
        self.assertEqual(result["operating_point"]["0.5"]["fp"], 1)
    def test_count_errors_include_false_positive_classes(self):
        result = e.counts([self.row(counts={"apple":1,"banana":1}, detectorStatus="available")], {"a": dict(counts={"apple":2})})
        self.assertEqual(result["mae"], 1)
        self.assertEqual(result["undercount_rate"], .5)
    def test_leakage_rejected(self):
        a, b = self.row(), self.row()
        b.update(file="b", split="train")
        with self.assertRaisesRegex(ValueError, "leakage"):
            e.report([a,b], {"a":dict(scene="same"), "b":dict(scene="same")})
    def test_partial_count_scope_excludes_unannotated_classes(self):
        result = e.counts([self.row(counts={"apple":1,"banana":5}, detectorStatus="available")],
                          {"a":dict(countScope=["apple"], counts={"apple":1})})
        self.assertEqual(result["pairs"], 1)
        self.assertEqual(result["positive_exact_rate"], 1)
    def test_invalid_annotation_rejected(self):
        with self.assertRaises(ValueError):
            e.report([self.row()], {"a":dict(counts={"apple":-1})})
    def test_negative_control(self):
        r = e.labels([dict(expected=[], detected=["apple"])])
        self.assertEqual(r["negative_false_positive_rate"], 1)
        self.assertIsNone(r["micro"]["recall"])

if __name__ == "__main__":
    unittest.main()
