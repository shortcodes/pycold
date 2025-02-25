import numpy as np
from pycold.ob_analyst import segmentation_floodfill, segmentation_slic
from pycold.ob_analyst import object_analysis
from pycold.ob_analyst import ObjectAnalystHPC
import yaml
# import matplotlib.pyplot as plt
import shutil

with open('tests/resources/test_config_obanalyst.yaml', 'r') as yaml_obj:
    test_config = yaml.safe_load(yaml_obj)

date = 730329

cm_array = np.load('tests/resources/cm_maps/CM_maps_730329_2000210.npy')
cm_array_l1 = np.load('tests/resources/cm_maps/CM_maps_730297_2000178.npy')
cm_date_array = np.load('tests/resources/cm_maps/CM_date_maps_730329_2000210.npy')
cm_array_l1_date = np.load('tests/resources/cm_maps/CM_date_maps_730297_2000178.npy')


def test_workflow():
    ob_analyst = ObjectAnalystHPC(test_config, starting_date=date, stack_path='tests/resources', result_path='tests/resources',
                                  thematic_path='tests/resources/feature_maps')
    ob_analyst.hpc_preparation()
    ob_analyst.obia_execute(date, method='slic')
    assert ob_analyst.is_finished_object_analysis(date_list=[date])
    shutil.rmtree(ob_analyst.obia_path)
    shutil.rmtree(ob_analyst.obcold_recg_path)


def test_segmentation():
    [object_map_s1, cm_date_array_updated, object_map_s2, s1_info] = segmentation_floodfill(cm_array,
                                                                     cm_date_array,
                                                                     cm_array_l1,
                                                                     cm_array_l1_date)
    assert len(np.unique(object_map_s1)) > 1
    assert len(np.unique(object_map_s2)) > 1


def test_object_analysis():
    [object_map_s1, cm_date_array_updated, object_map_s2, s1_info] = segmentation_floodfill(cm_array,
                                                                             cm_date_array, cm_array_l1,
                                                                             cm_array_l1_date)
    classification_map = np.load('tests/resources/feature_maps/yearlyclassification_1999.npy')
    change_map = object_analysis(object_map_s1, object_map_s2, s1_info, classification_map)
    # import matplotlib.pyplot as plt
    # plt.imshow(change_map)
    # test_config = yaml.safe_load(yaml_obj)
    assert len(np.unique(change_map)) > 1

    # import matplotlib
    # from random import random
    # import matplotlib.pyplot as plt
    # colors = [(1,1,1)] + [(random(),random(),random()) for i in range(255)]
    # new_map = matplotlib.colors.LinearSegmentedColormap.from_list('new_map', colors, N=256)
    # plt.imshow(object_map_s1, cmap=new_map)


def test_get_lastyear_cmap_fromdate():
    ob_analyst = ObjectAnalystHPC(test_config, starting_date=date - 366, stack_path='tests/resources', result_path='tests/resources',
                                  thematic_path='tests/resources/feature_maps')
    cmap = ob_analyst.get_lastyear_cmap_fromdate(date)
    assert cmap is not None


