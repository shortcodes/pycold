from libc.stdlib cimport malloc
from libc.string cimport strcpy, strlen
import numpy as np
# "cimport" is used to import special compile-time information
# about the numpy module (this is stored in a file numpy.pxd which is
# currently part of the Cython distribution).
cimport numpy as np
import math
from libcpp cimport bool
from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from collections import namedtuple
from copy import deepcopy


try:
    import typing
    import dataclasses
except ImportError:
    pass  # The modules don't actually have to exists for Cython to use them as annotations

cdef int NUM_FC = 40  # define the maximum number of outputted curves
cdef int NUM_NRT_QUEUE = 300
DEF DEFAULT_CONSE = 5
DEF NRT_BAND = 6

reccg_dt = np.dtype([('t_start', np.int32),  # time when series model gets started
                     ('t_end', np.int32),  # time when series model gets ended
                     ('t_break', np.int32),  # time when the first break (change) is observed
                     ('pos', np.int32),  # the location of each time series model
                     ('num_obs', np.int32),  # the number of "good" observations used for model estimation
                     ('category', np.short),  # the quality of the model estimation (what model is used, what process is used)
                     ('change_prob', np.short),  # the probability of a pixel that have undergone change (between 0 and 100)
                     ('coefs', np.float32, (7, 8)),  # coefficients for each time series model for each spectral band
                     ('rmse', np.float32, 7),  # RMSE for each time series model for each spectral band
                     ('magnitude', np.float32, 7)])  # the magnitude of change difference between model prediction
                                          # and observation for each spectral band)

sccd_dt = np.dtype([('t_start', np.int32),
                        ('t_break', np.int32),
                        ('num_obs', np.int32),
                        ('coefs', np.float32, (6, 6)),
                        ('rmse', np.float32, 6),
                        ('magnitude', np.float32, 6)],
                        align=True)

nrtqueue_dt = np.dtype([('clry', np.short, 6), ('clrx_since1982', np.short)], align=True)
nrtmodel_dt = np.dtype([('t_start_since1982', np.short), ('num_obs', np.short), ('obs', np.short, (6, 5)),
                         ('obs_date_since1982', np.short, 5), ('covariance', np.float32, (6, 36)),
                         ('nrt_coefs', np.float32, (6, 6)), ('H', np.float32, 6), ('rmse_sum', np.uint32, 6),
                         ('cm_outputs', np.short), ('cm_outputs_date', np.short), ('change_prob', np.ubyte)], align=True)


cdef extern from "../../cxx/output.h":
    ctypedef struct Output_t:
        int t_start
        int t_end
        int t_break
        int pos
        int num_obs
        short int category
        short int change_prob
        float coefs[7][8]
        float rmse[7]
        float magnitude[7]

cdef extern from "../../cxx/output.h":
    ctypedef struct Output_sccd:
        int t_start
        int t_break
        int num_obs
        float coefs[NRT_BAND][6]
        float rmse[NRT_BAND]
        float magnitude[NRT_BAND]

cdef extern from "../../cxx/output.h":
    ctypedef struct output_nrtqueue:
        short int clry[NRT_BAND]
        short int clrx_since1982
        
cdef extern from "../../cxx/output.h":
    ctypedef struct output_nrtmodel:
        short int t_start_since1982
        short int num_obs
        short int obs[NRT_BAND][DEFAULT_CONSE]
        short int obs_date_since1982[DEFAULT_CONSE]
        float covariance[NRT_BAND][36]
        float nrt_coefs[NRT_BAND][6]
        float H[NRT_BAND]
        unsigned int rmse_sum[NRT_BAND]
        short int cm_outputs;
        short int cm_outputs_date;
        unsigned char change_prob;
 
cdef Output_sccd t
cdef output_nrtqueue t2
cdef output_nrtmodel t3


cdef extern from "../../cxx/cold.h":
    cdef int cold(long *buf_b, long *buf_g, long *buf_r, long *buf_n, long *buf_s1, long *buf_s2,
                  long *buf_t, long *fmask_buf, long *valid_date_array, int valid_num_scenes, int pos, 
                  double tcg, int conse, bool b_output_cm, int starting_date, bool b_c2, Output_t *rec_cg,
                  int *num_fc, int cm_output_interval, short int *cm_outputs, 
                  short int *cm_outputs_date);


cdef extern from "../../cxx/cold.h":
    cdef int obcold_reconstruction_procedure(long *buf_b, long *buf_g, long *buf_r, long *buf_n, long *buf_s1,
    long *buf_s2, long *buf_t,  long *fmask_buf, long *valid_date_array, int valid_num_scenes, long *break_dates,
    int break_date_len, int pos, bool b_c2, int conse, Output_t *rec_cg, int *num_fc)



cdef extern from "../../cxx/s_ccd.h":
    cdef int sccd(long *buf_b, long *buf_g, long *buf_r, long *buf_n, long *buf_s1, long *buf_s2, long *buf_t,
                  long *fmask_buf, long *valid_date_array, int valid_num_scenes, double tcg, int *num_fc, int *nrt_mode,
                  Output_sccd *rec_cg, output_nrtmodel *nrt_model, int *num_nrt_queue, output_nrtqueue *nrt_queue,
                  short int *min_rmse, int cm_output_interval, int starting_date, int conse, bool b_c2,
                  short int* cm_outputs, short int* cm_outputs_date, bool b_pinpoint)



#cdef class SccdOutput:
#    cdef public int position
#    cdef public np.ndarray rec_cg
#    cdef public int nrt_mode
#    cdef public tuple nrt_model
#    cdef public np.ndarray nrt_queue
#    def __init__(self, position, rec_cg, nrt_mode, nrt_model, nrt_queue):
#        self.position = position
#        self.rec_cg = rec_cg
#        self.nrt_mode = nrt_mode
#        self.nrt_model = nrt_model
#        self.nrt_queue = nrt_queue
SccdOutput = namedtuple("SccdOutput", "position rec_cg min_rmse nrt_mode nrt_model nrt_queue")

def test_func():
    """
    This is a docstring
    """
    return None

def cold_detect(np.ndarray[np.int64_t, ndim=1] dates, np.ndarray[np.int64_t, ndim=1] ts_b, np.ndarray[np.int64_t, ndim=1] ts_g,
                np.ndarray[np.int64_t, ndim=1] ts_r, np.ndarray[np.int64_t, ndim=1] ts_n, np.ndarray[np.int64_t, ndim=1] ts_s1,
                np.ndarray[np.int64_t, ndim=1] ts_s2, np.ndarray[np.int64_t, ndim=1] ts_t, np.ndarray[np.int64_t, ndim=1] qas,
                double t_cg = 15.0863, int pos=1, int conse=6, bint b_output_cm=False,
                int starting_date=0, int n_cm=0, int cm_output_interval=0, bint b_c2=False):
    """
    Helper function to do COLD algorithm.

    	Parameters
    	----------
    	dates: 1d array of shape(observation numbers), list of ordinal dates
    	ts_b: 1d array of shape(observation numbers), time series of blue band.
    	ts_g: 1d array of shape(observation numbers), time series of green band
    	ts_r: 1d array of shape(observation numbers), time series of red band
    	ts_n: 1d array of shape(observation numbers), time series of nir band
   	    ts_s1: 1d array of shape(observation numbers), time series of swir1 band
    	ts_s2: 1d array of shape(observation numbers), time series of swir2 band
    	ts_t: 1d array of shape(observation numbers), time series of thermal band
    	qas: 1d array, the QA cfmask bands. '0' - clear; '1' - water; '2' - shadow; '3' - snow; '4' - cloud
    	t_cg: threshold of change magnitude, default is chi2.ppf(0.99,5)
         pos: position id of the pixel
    	conse: consecutive observation number
    	b_output_cm: bool, 'True' means outputting change magnitude and change magnitude dates, only for object-based COLD
    	starting_date: the starting date of the whole dataset to enable reconstruct CM_date,
                   	all pixels for a tile should have the same date, only for b_output_cm is True
        b_c2: bool, a temporal parameter to indicate if collection 2. C2 needs ignoring thermal band for valid pixel test due to the current low quality
    	cm_output_interval: the temporal interval of outputting change magnitudes
    	Note that passing 2-d array to c as 2-d pointer does not work, so have to pass separate bands
    	Returns
    	----------
    	change records: the COLD outputs that characterizes each temporal segment
    """

    cdef int valid_num_scenes = qas.shape[0]
    # allocate memory for rec_cg
    cdef int num_fc = 0
    cdef Output_t t
    cdef Output_t* rec_cg = <Output_t*> PyMem_Malloc(NUM_FC * sizeof(t))

    # make sure it is c contiguous array
#    if dates.flags['C_CONTIGUOUS'] == False:
#        dates = np.ascontiguousarray(dates)
#    if ts_b.flags['C_CONTIGUOUS'] == False:
#        ts_b = np.ascontiguousarray(ts_b)
#    if ts_g.flags['C_CONTIGUOUS'] == False:
#        ts_g = np.ascontiguousarray(ts_g)
#    if ts_r.flags['C_CONTIGUOUS'] == False:
#        ts_r = np.ascontiguousarray(ts_r)
#    if ts_n.flags['C_CONTIGUOUS'] == False:
#        ts_n = np.ascontiguousarray(ts_n)
#    if ts_s1.flags['C_CONTIGUOUS'] == False:
#        ts_s1 = np.ascontiguousarray(ts_s1)
#    if ts_s2.flags['C_CONTIGUOUS'] == False:
#        ts_s2 = np.ascontiguousarray(ts_s2)
#    if ts_t.flags['C_CONTIGUOUS'] == False:
#        ts_t = np.ascontiguousarray(ts_t)
#    if qas.flags['C_CONTIGUOUS'] == False:
#        qas = np.ascontiguousarray(qas)
    
    cdef long [:] dates_view = dates
    cdef long [:] ts_b_view = ts_b
    cdef long [:] ts_g_view = ts_g
    cdef long [:] ts_r_view = ts_r
    cdef long [:] ts_n_view = ts_n
    cdef long [:] ts_s1_view = ts_s1
    cdef long [:] ts_s2_view = ts_s2
    cdef long [:] ts_t_view = ts_t
    cdef long [:] qas_view = qas


    assert ts_b_view.shape[0] == dates_view.shape[0]
    assert ts_g_view.shape[0] == dates_view.shape[0]
    assert ts_r_view.shape[0] == dates_view.shape[0]
    assert ts_n_view.shape[0] == dates_view.shape[0]
    assert ts_s1_view.shape[0] == dates_view.shape[0]
    assert ts_s2_view.shape[0] == dates_view.shape[0]
    assert ts_t_view.shape[0] == dates_view.shape[0]
    assert qas_view.shape[0] == dates_view.shape[0]

    # cm_outputs and cm_outputs_date are for object-based cold
    if b_output_cm == True:
        if cm_output_interval == 0:
           cm_output_interval = 60
        if starting_date == 0:
           starting_date = dates[0]
        if n_cm == 0:
           n_cm = math.ceil((dates[valid_num_scenes-1] - starting_date + 1) / cm_output_interval) + 1
        cm_outputs = np.full(n_cm, -9999, dtype=np.short)
        cm_outputs_date = np.full(n_cm, -9999, dtype=np.short)
    # set the length to 1 to save memory, as they won't be assigned values
    else:  
        cm_outputs = np.full(1, -9999, dtype=np.short)
        cm_outputs_date = np.full(1, -9999, dtype=np.short)
    cdef short [:] cm_outputs_view = cm_outputs  # memory view
    cdef short [:] cm_outputs_date_view = cm_outputs_date  # memory view

    result = cold(&ts_b_view[0], &ts_g_view[0], &ts_r_view[0], &ts_n_view[0], &ts_s1_view[0], &ts_s2_view[0], &ts_t_view[0],
                 &qas_view[0], &dates_view[0], valid_num_scenes, pos, t_cg, conse, b_output_cm,
                 starting_date, b_c2, rec_cg, &num_fc, cm_output_interval, &cm_outputs_view[0], &cm_outputs_date_view[0])
    if result != 0:
        raise RuntimeError("cold function fails for pos = {} ".format(pos))
    else:
        if num_fc <= 0:
            raise Exception("The COLD function has no change records outputted for pos = {} (possibly due to no enough clear observation)".format(pos))
        else:
            if b_output_cm == False:
                return np.asarray(<Output_t[:num_fc]>rec_cg) # np.asarray uses also the buffer-protocol and is able to construct
                                                             # a dtype-object from cython's array
            else:  # for object-based COLD
                return [np.asarray(<Output_t[:num_fc]>rec_cg), cm_outputs, cm_outputs_date]


def obcold_reconstruct(np.ndarray[np.int64_t, ndim=1] dates, np.ndarray[np.int64_t, ndim=1] ts_b, np.ndarray[np.int64_t, ndim=1] ts_g,
                np.ndarray[np.int64_t, ndim=1] ts_r, np.ndarray[np.int64_t, ndim=1] ts_n, np.ndarray[np.int64_t, ndim=1] ts_s1,
                np.ndarray[np.int64_t, ndim=1] ts_s2, np.ndarray[np.int64_t, ndim=1] ts_t, np.ndarray[np.int64_t, ndim=1] qas,
                np.ndarray[np.int64_t, ndim=1] break_dates, int pos=1, int conse=6, bint b_c2=False):
    """
    Helper function to do COLD algorithm.

    	Parameters
    	----------
    	dates: 1d array of shape(observation numbers), list of ordinal dates
    	ts_b: 1d array of shape(observation numbers), time series of blue band.
    	ts_g: 1d array of shape(observation numbers), time series of green band
    	ts_r: 1d array of shape(observation numbers), time series of red band
    	ts_n: 1d array of shape(observation numbers), time series of nir band
   	    ts_s1: 1d array of shape(observation numbers), time series of swir1 band
    	ts_s2: 1d array of shape(observation numbers), time series of swir2 band
    	ts_t: 1d array of shape(observation numbers), time series of thermal band
    	qas: 1d array, the QA cfmask bands. '0' - clear; '1' - water; '2' - shadow; '3' - snow; '4' - cloud
    	break_dates: 1d array, the break dates obtained from other procedures such as obia
    	conse: consecutive observation number (for calculating change magnitudes)
    	b_c2: bool, a temporal parameter to indicate if collection 2. C2 needs ignoring thermal band for valid pixel test due to its current low quality
    	Note that passing 2-d array to c as 2-d pointer does not work, so have to pass separate bands
    	Returns
    	----------
    	change records: the COLD outputs that characterizes each temporal segment
    """

    cdef int valid_num_scenes = qas.shape[0]
    cdef int break_date_len = break_dates.shape[0]
    # allocate memory for rec_cg
    cdef int num_fc = 0
    cdef Output_t t
    cdef Output_t* rec_cg = <Output_t*> PyMem_Malloc(NUM_FC * sizeof(t))

    cdef long [:] dates_view = dates
    cdef long [:] ts_b_view = ts_b
    cdef long [:] ts_g_view = ts_g
    cdef long [:] ts_r_view = ts_r
    cdef long [:] ts_n_view = ts_n
    cdef long [:] ts_s1_view = ts_s1
    cdef long [:] ts_s2_view = ts_s2
    cdef long [:] ts_t_view = ts_t
    cdef long [:] qas_view = qas
    cdef long [:] break_dates_view = break_dates

    assert ts_b_view.shape[0] == dates_view.shape[0]
    assert ts_g_view.shape[0] == dates_view.shape[0]
    assert ts_r_view.shape[0] == dates_view.shape[0]
    assert ts_n_view.shape[0] == dates_view.shape[0]
    assert ts_s1_view.shape[0] == dates_view.shape[0]
    assert ts_s2_view.shape[0] == dates_view.shape[0]
    assert ts_t_view.shape[0] == dates_view.shape[0]
    assert qas_view.shape[0] == dates_view.shape[0]

    result = obcold_reconstruction_procedure(&ts_b_view[0], &ts_g_view[0], &ts_r_view[0], &ts_n_view[0], &ts_s1_view[0],
     &ts_s2_view[0], &ts_t_view[0], &qas_view[0], &dates_view[0], valid_num_scenes, &break_dates_view[0], break_date_len,
      pos, b_c2, conse, rec_cg, &num_fc)
    if result != 0:
        raise RuntimeError("cold function fails for pos = {} ".format(pos))
    else:
        if num_fc <= 0:
            raise Exception("The reconstruct function has no change records outputted for pos = {} (possibly due to no enough clear observation)".format(pos))
        else:
            return np.asarray(<Output_t[:num_fc]>rec_cg) # np.asarray uses also the buffer-protocol and is able to construct a dtype-object from cython's array


def sccd_detect(np.ndarray[np.int64_t, ndim=1] dates, np.ndarray[np.int64_t, ndim=1] ts_b, np.ndarray[np.int64_t, ndim=1] ts_g,
                np.ndarray[np.int64_t, ndim=1] ts_r, np.ndarray[np.int64_t, ndim=1] ts_n, np.ndarray[np.int64_t, ndim=1] ts_s1,
                np.ndarray[np.int64_t, ndim=1] ts_s2, np.ndarray[np.int64_t, ndim=1] ts_t, np.ndarray[np.int64_t, ndim=1] qas,
                bint b_output_cm=False, int starting_date=0, int n_cm=0, int cm_output_interval=60, double t_cg = 15.0863, int pos=1,
                int conse=5, bint b_c2=False):
    """
    S-CCD processing. It is required to be done before near real time monitoring

    	Parameters
    	----------
    	dates: 1d array of shape(observation numbers), list of ordinal dates
    	ts_b: 1d array of shape(observation numbers), time series of blue band.
    	ts_g: 1d array of shape(observation numbers), time series of green band
    	ts_r: 1d array of shape(observation numbers), time series of red band
    	ts_n: 1d array of shape(observation numbers), time series of nir band
   	    ts_s1: 1d array of shape(observation numbers), time series of swir1 band
    	ts_s2: 1d array of shape(observation numbers), time series of swir2 band
    	ts_t: 1d array of shape(observation numbers), time series of thermal band
    	qas: 1d array, the QA cfmask bands. '0' - clear; '1' - water; '2' - shadow; '3' - snow; '4' - cloud
    	starting_date: the global starting date of the dataset
    	n_cm: the global number of change magnitude snapshots
    	cm_output_interval: the interval of change magnitude output
    	t_cg: threshold of change magnitude, default is chi2.ppf(0.99,5)
        pos: position id of the pixel
    	conse: consecutive observation number
    	b_c2: bool, a temporal parameter to indicate if collection 2. C2 needs ignoring thermal band for valid pixel test due to its current low quality
    	Note that passing 2-d array to c as 2-d pointer does not work, so have to pass separate bands
    	Returns
    	----------
        namedtupe: SccdOutput
            change records: the S-CCD outputs that characterizes each temporal segment
            rec_cg:
            min_rmse
            int nrt_mode,             /* O: 0 - void; 1 - monitor mode for standard; 2 - queue mode for standard; 3 - new change; 4 - monitor mode for snow; 5 - queue mode for snow */
            output_nrtmodel: nrt model if monitor mode, empty if queue mode
            output_nrtqueue: obs queue if queue mode, empty if monitor mode
    """
    if dates.flags['C_CONTIGUOUS'] == False:
       dates = np.ascontiguousarray(dates)
    if ts_b.flags['C_CONTIGUOUS'] == False:
        ts_b = np.ascontiguousarray(ts_b)
    if ts_g.flags['C_CONTIGUOUS'] == False:
        ts_g = np.ascontiguousarray(ts_g)
    if ts_r.flags['C_CONTIGUOUS'] == False:
        ts_r = np.ascontiguousarray(ts_r)
    if ts_n.flags['C_CONTIGUOUS'] == False:
        ts_n = np.ascontiguousarray(ts_n)
    if ts_s1.flags['C_CONTIGUOUS'] == False:
        ts_s1 = np.ascontiguousarray(ts_s1)
    if ts_s2.flags['C_CONTIGUOUS'] == False:
        ts_s2 = np.ascontiguousarray(ts_s2)
    if ts_t.flags['C_CONTIGUOUS'] == False:
        ts_t = np.ascontiguousarray(ts_t)
    if qas.flags['C_CONTIGUOUS'] == False:
        qas = np.ascontiguousarray(qas)
        
    if conse > DEFAULT_CONSE:
        raise RuntimeError("The inputted conse is longer than the maximum conse for S-CCD: {}".format(DEFAULT_CONSE))

    cdef int valid_num_scenes = qas.shape[0]
    # allocate memory for rec_cg
    cdef int num_fc = 0
    cdef int num_nrt_queue = 0
    cdef Output_sccd* rec_cg = <Output_sccd*> PyMem_Malloc(NUM_FC * sizeof(t))
    cdef output_nrtqueue* nrt_queue = <output_nrtqueue*> PyMem_Malloc(NUM_NRT_QUEUE * sizeof(t2))
    cdef output_nrtmodel* nrt_model = <output_nrtmodel*> PyMem_Malloc(sizeof(t3))
    cdef int nrt_mode = 0
    # initiate minimum rmse
    min_rmse = np.full(NRT_BAND, 0, dtype=np.short)

    # memory view
    cdef long [:] dates_view = dates
    cdef long [:] ts_b_view = ts_b
    cdef long [:] ts_g_view = ts_g
    cdef long [:] ts_r_view = ts_r
    cdef long [:] ts_n_view = ts_n
    cdef long [:] ts_s1_view = ts_s1
    cdef long [:] ts_s2_view = ts_s2
    cdef long [:] ts_t_view = ts_t
    cdef long [:] qas_view = qas
    cdef short [:] min_rmse_view = min_rmse


    assert ts_b_view.shape[0] == dates_view.shape[0]
    assert ts_g_view.shape[0] == dates_view.shape[0]
    assert ts_r_view.shape[0] == dates_view.shape[0]
    assert ts_n_view.shape[0] == dates_view.shape[0]
    assert ts_s1_view.shape[0] == dates_view.shape[0]
    assert ts_s2_view.shape[0] == dates_view.shape[0]
    assert ts_t_view.shape[0] == dates_view.shape[0]
    assert qas_view.shape[0] == dates_view.shape[0]

    if b_output_cm == True:
        if starting_date == 0:
           starting_date = dates[0]
        if n_cm == 0:
           n_cm = math.ceil((dates[valid_num_scenes-1] - starting_date + 1) / cm_output_interval)
        cm_outputs = np.full(n_cm, -9999, dtype=np.short)
        cm_outputs_date = np.full(n_cm, -9999, dtype=np.short)
    # set the length to 1 to save memory, as they won't be assigned values
    else:  
        cm_outputs = np.full(1, -9999, dtype=np.short)
        cm_outputs_date = np.full(1, -9999, dtype=np.short)
        cm_output_interval = 999999   # give any extreme large value
        
    cdef short [:] cm_outputs_view = cm_outputs  # memory view
    cdef short [:] cm_outputs_date_view = cm_outputs_date  # memory view

    result = sccd(&ts_b_view[0], &ts_g_view[0], &ts_r_view[0], &ts_n_view[0], &ts_s1_view[0], &ts_s2_view[0],
                  &ts_t_view[0], &qas_view[0], &dates_view[0], valid_num_scenes, t_cg, &num_fc, &nrt_mode, rec_cg,
                  nrt_model, &num_nrt_queue, nrt_queue, &min_rmse_view[0], cm_output_interval, starting_date, 
                  conse, b_c2, &cm_outputs_view[0] , &cm_outputs_date_view[0], False)
    if result != 0:
        raise RuntimeError("S-CCD function fails for pos = {} ".format(pos))
    else:
        if nrt_mode < 0:
            raise RuntimeError("No correct nrt_mode returned for pos = {} ".format(pos))
        else:
            if num_fc > 0:
                output_rec_cg = np.asarray(<Output_sccd[:num_fc]>rec_cg)
            else:
                output_rec_cg = np.array([])
                

            if nrt_mode == 1 or nrt_mode == 3:  # monitor mode
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  np.asarray(<output_nrtmodel[:1]>nrt_model), np.array([]))
            elif nrt_mode == 2 or nrt_mode == 4:  # queue mode
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  np.array([]),np.asarray(<output_nrtqueue[:num_nrt_queue]>nrt_queue))
            elif nrt_mode == 5:  # queue recent
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  np.asarray(<output_nrtmodel[:1]>nrt_model),
                                  np.asarray(<output_nrtqueue[:num_nrt_queue]>nrt_queue))
            elif nrt_mode == 0:  # void mode
                return SccdOutput(pos, np.array([]), min_rmse, nrt_mode, np.array([]),
                                  np.array([]))


def sccd_update(sccd_pack, np.ndarray[np.int64_t, ndim=1] dates, np.ndarray[np.int64_t, ndim=1] ts_b,
                np.ndarray[np.int64_t, ndim=1] ts_g, np.ndarray[np.int64_t, ndim=1] ts_r,
                np.ndarray[np.int64_t, ndim=1] ts_n, np.ndarray[np.int64_t, ndim=1] ts_s1,
                np.ndarray[np.int64_t, ndim=1] ts_s2, np.ndarray[np.int64_t, ndim=1] ts_t,
                np.ndarray[np.int64_t, ndim=1] qas, double t_cg = 15.0863, int pos=1, int conse=5, bint b_c2=False,
                bint b_pinpoint=False):
    """
    SCCD online update for new observations
       Parameters
       ----------
       sccd_pack: a namedtuple of SccdOutput
       dates: 1d array of shape(observation numbers), list of ordinal dates
       ts_b: 1d array of shape(observation numbers), time series of blue band.
       ts_g: 1d array of shape(observation numbers), time series of green band
       ts_r: 1d array of shape(observation numbers), time series of red band
       ts_n: 1d array of shape(observation numbers), time series of nir band
       ts_s1: 1d array of shape(observation numbers), time series of swir1 band
       ts_s2: 1d array of shape(observation numbers), time series of swir2 band
       ts_t: 1d array of shape(observation numbers), time series of thermal band
       qas: 1d array, the QA cfmask bands. '0' - clear; '1' - water; '2' - shadow; '3' - snow; '4' - cloud
       t_cg: threshold of change magnitude, default is chi2.ppf(0.99,5)
       pos: position id of the pixel
       conse: consecutive observation number
       b_c2: bool, a temporal parameter to indicate if collection 2. C2 needs ignoring thermal band for valid pixel test due to its current low quality
       b_pinpoint: bool, pinpoint the most likely to be change in the epoch
       Note that passing 2-d array to c as 2-d pointer does not work, so have to pass separate bands
       Returns
       ----------
       namedtupe: SccdOutput
            rec_cg: the S-CCD outputs that characterizes each temporal segment
            min_rmse
            int nrt_mode,             /* O: 0 - void; 1 - monitor mode for standard; 2 - queue mode for standard;
                                            3 - monitor mode for snow; 4 - queue mode for snow; 5 - new queue */
            nrt_model: nrt model if monitor mode, empty if queue mode
            nrt_queue: obs queue if queue mode, empty if monitor mode
    """
    if dates.flags['C_CONTIGUOUS'] == False:
       dates = np.ascontiguousarray(dates)
    if ts_b.flags['C_CONTIGUOUS'] == False:
        ts_b = np.ascontiguousarray(ts_b)
    if ts_g.flags['C_CONTIGUOUS'] == False:
        ts_g = np.ascontiguousarray(ts_g)
    if ts_r.flags['C_CONTIGUOUS'] == False:
        ts_r = np.ascontiguousarray(ts_r)
    if ts_n.flags['C_CONTIGUOUS'] == False:
        ts_n = np.ascontiguousarray(ts_n)
    if ts_s1.flags['C_CONTIGUOUS'] == False:
        ts_s1 = np.ascontiguousarray(ts_s1)
    if ts_s2.flags['C_CONTIGUOUS'] == False:
        ts_s2 = np.ascontiguousarray(ts_s2)
    if ts_t.flags['C_CONTIGUOUS'] == False:
        ts_t = np.ascontiguousarray(ts_t)
    if qas.flags['C_CONTIGUOUS'] == False:
        qas = np.ascontiguousarray(qas)

    # sccd_pack_copy = deepcopy(sccd_pack)

    cdef int valid_num_scenes = qas.shape[0]
    # allocate memory for rec_cg
    # cdef int num_fc = 0
    # cdef int num_nrt_queue = 0
    cdef int nrt_mode = sccd_pack.nrt_mode
    cdef int num_fc = len(sccd_pack.rec_cg)
    cdef int num_nrt_queue = len(sccd_pack.nrt_queue)

    # use an extreme value to enable only one cm output
    cdef int cm_output_interval = 999999
    cdef int starting_date = 0
    cdef int n_cm = 1
    
    # grab inputs from the input
    rec_cg_new = np.empty(NUM_FC, dtype=sccd_dt)
    if num_fc > 0:
        rec_cg_new[0:num_fc] = sccd_pack.rec_cg[0:num_fc]
    # rec_cg = <Output_sccd*> PyMem_Malloc(NUM_FC * sizeof(t))

    nrt_queue_new = np.empty(NUM_NRT_QUEUE, dtype=nrtqueue_dt)
    if num_nrt_queue > 0:
        nrt_queue_new[0:num_nrt_queue] = sccd_pack.nrt_queue[0:num_nrt_queue]

    if nrt_mode == 1 or nrt_mode == 3:
        nrt_model_new = sccd_pack.nrt_model.copy()
    else:
        nrt_model_new = np.empty(1, dtype=nrtmodel_dt)

    min_rmse = sccd_pack.min_rmse

    # memory view
    cdef Output_sccd [:] rec_cg_view = rec_cg_new
    cdef output_nrtqueue [:] nrt_queue_view = nrt_queue_new
    cdef output_nrtmodel [:] nrt_model_view = nrt_model_new
    cdef short [:] min_rmse_view = min_rmse
    cdef long [:] dates_view = dates
    cdef long [:] ts_b_view = ts_b
    cdef long [:] ts_g_view = ts_g
    cdef long [:] ts_r_view = ts_r
    cdef long [:] ts_n_view = ts_n
    cdef long [:] ts_s1_view = ts_s1
    cdef long [:] ts_s2_view = ts_s2
    cdef long [:] ts_t_view = ts_t
    cdef long [:] qas_view = qas

    # assert the length
    assert ts_b_view.shape[0] == dates_view.shape[0]
    assert ts_g_view.shape[0] == dates_view.shape[0]
    assert ts_r_view.shape[0] == dates_view.shape[0]
    assert ts_n_view.shape[0] == dates_view.shape[0]
    assert ts_s1_view.shape[0] == dates_view.shape[0]
    assert ts_s2_view.shape[0] == dates_view.shape[0]
    assert ts_t_view.shape[0] == dates_view.shape[0]
    assert qas_view.shape[0] == dates_view.shape[0]

    cm_outputs = np.full(1, -9999, dtype=np.short)
    cm_outputs_date = np.full(1, -9999, dtype=np.short)
    cdef short [:] cm_outputs_view = cm_outputs  # memory view
    cdef short [:] cm_outputs_date_view = cm_outputs_date  # memory view    
    
    result = sccd(&ts_b_view[0], &ts_g_view[0], &ts_r_view[0], &ts_n_view[0], &ts_s1_view[0], &ts_s2_view[0],
                  &ts_t_view[0], &qas_view[0], &dates_view[0], valid_num_scenes, t_cg, &num_fc, &nrt_mode, &rec_cg_view[0],
                  &nrt_model_view[0], &num_nrt_queue, &nrt_queue_view[0], &min_rmse_view[0], cm_output_interval, starting_date,
                  conse, b_c2, &cm_outputs_view[0], &cm_outputs_date_view[0], b_pinpoint)
    if result != 0:
        raise RuntimeError("sccd_update function fails for pos = {} ".format(pos))
    else:
        if nrt_mode < 0:
            raise RuntimeError("No correct nrt_mode returned for pos = {} ".format(pos))
        else:
            # sccd_pack_copy = None
            if num_fc > 0:
                output_rec_cg = rec_cg_new[0:num_fc]
            else:
                output_rec_cg = np.array([])

            if nrt_mode == 1 or nrt_mode == 3:  # monitor mode
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  nrt_model_new, np.array([]))
            elif nrt_mode == 2 or nrt_mode == 4:  # queue mode
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  np.array([]), nrt_queue_new[0:num_nrt_queue])
            elif nrt_mode == 5:  # queue recent
                return SccdOutput(pos, output_rec_cg, min_rmse, nrt_mode,
                                  nrt_model_new, nrt_queue_new[0:num_nrt_queue])
            elif nrt_mode == 0:  # void mode
                return SccdOutput(pos, np.array([]), min_rmse, nrt_mode, np.array([]), np.array([]))



