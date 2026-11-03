import unittest
from benchmark import summarize, select_threshold, partition

class BenchmarkTests(unittest.TestCase):
    def test_negatives_are_not_removed(self):
        images=[{'id':1},{'id':2}]
        truth=[{'image_id':1,'category_id':53}]
        records={1:{'detections':[{'category_id':53,'score':.9}]},2:{'detections':[{'category_id':53,'score':.9}]}}
        result=summarize(images,truth,records,.5,{53:'apple'})
        self.assertEqual(result['micro']['recall'],1)
        self.assertEqual(result['micro']['precision'],.5)
        self.assertEqual(result['negative_false_positive_rate'],1)
    def test_crowd_excluded_from_counts_not_presence(self):
        result=summarize([{'id':1}],[{'image_id':1,'category_id':53,'iscrowd':1}],{1:{'detections':[]}},.5,{53:'apple'})
        self.assertEqual(result['micro']['recall'],0)
        self.assertIsNone(result['positive_count_mae'])
    def test_threshold_never_selected_without_precision(self):
        self.assertIsNone(select_threshold([(.1,{'micro':{'recall':.9,'precision':.3}})],.9))
    def test_threshold_maximizes_recall_subject_to_precision(self):
        sweep=[(.1,{'micro':{'recall':.9,'precision':.3}}),(.3,{'micro':{'recall':.8,'precision':.91}}),(.5,{'micro':{'recall':.7,'precision':.98}})]
        self.assertEqual(select_threshold(sweep,.9),.3)
    def test_no_predictions_means_zero_recall(self):
        r=summarize([{'id':1}],[{'image_id':1,'category_id':53}],{1:{'detections':[]}},.5,{53:'apple'})
        self.assertEqual(r['micro']['recall'],0)
        self.assertEqual(r['positive_count_mae'],1)
    def test_split_is_stable(self):
        self.assertEqual([partition(i) for i in range(100)], [partition(i) for i in range(100)])
        self.assertEqual(set(partition(i) for i in range(100)),{'calibration','evaluation'})

if __name__=='__main__': unittest.main()
