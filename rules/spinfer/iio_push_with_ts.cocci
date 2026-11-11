@@
expression E2, E0, E1;
@@
- iio_push_to_buffers_with_timestamp(E0, &E1, E2); 
+ iio_push_to_buffers_with_ts(E0, &E1, sizeof(E1), E2); 
// Infered from: (19/{before.c,after.c}: dln2_adc_trigger_h), (17/{before.c,after.c}: ad7779_trigger_handler), (16/{before.c,after.c}: ad7768_trigger_handler), (15/{before.c,after.c}: ad7606_trigger_handler), (13/{before.c,after.c}: ad7380_trigger_handler), (11/{before.c,after.c}: ad7266_trigger_handler), (08/{before.c,after.c}: ad4000_trigger_handler), (07/{before.c,after.c}: ad2s1210_trigger_handler), (03/{before.c,after.c}: tmp006_trigger_handler), (01/{before.c,after.c}: temperature_proc_event)
// Recall: 0.44, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
identifier I2, I3;
expression E4, E0, E1;
@@
- iio_push_to_buffers_with_timestamp(E0, E1->I2.I3, E4); 
+ iio_push_to_buffers_with_ts(E0, &E1->I2, sizeof(E1->I2), E4); 
// Infered from: (09/{before.c,after.c}: ad4030_trigger_handler), (05/{before.c,after.c}: ads131e08_trigger_handler)
// Recall: 0.09, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
identifier I0, I1, I2, I3;
expression E4, E5, E6;
typedef int64_t;
@@
  void hid_sensor_push_data(struct iio_dev *I0, void *I1, int I2, int64_t I3)  
  {
  ...
- iio_push_to_buffers_with_timestamp(E4, E5, E6); 
+ iio_push_to_buffers_with_ts(E4, E5, I2, E6); 
  ...
  }
// Infered from: (06/{before.c,after.c}: hid_sensor_push_data)
// Recall: 0.04, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
identifier I2;
expression E5, E0, E1, E3, E4;
typedef s16;
@@
- E0 = irsd200_read_data(E1, (s16 *)I2); 
+ memset(&scan, 0, sizeof(scan)); 
+ E0 = irsd200_read_data(E1, &scan.channel); 
  ...
- iio_push_to_buffers_with_timestamp(E3, E4, E5); 
+ iio_push_to_buffers_with_ts(E3, &scan, sizeof(scan), iio_get_time_ns(E3)); 
// Infered from: (00/{before.c,after.c}: irsd200_trigger_handler)
// Recall: 0.11, Precision: 1.00, Matching recall: 0.71

// ---------------------------------------------
@@
expression E2, E0, E1;
@@
- iio_push_to_buffers_with_timestamp(E0, E1, E2); 
+ iio_push_to_buffers_with_ts(E0, E1, sizeof(E1), E2); 
// Infered from: (18/{before.c,after.c}: ad7923_trigger_handler), (14/{before.c,after.c}: ad7476_trigger_handler), (12/{before.c,after.c}: ad7298_trigger_handler), (10/{before.c,after.c}: ad4695_trigger_handler), (02/{before.c,after.c}: maxim_thermocouple_trigger_handler)
// False positives: (00/after.c: irsd200_trigger_handler), (01/after.c: temperature_proc_event), (03/after.c: tmp006_trigger_handler), (04/after.c: iio_simple_dummy_trigger_h), (05/after.c: ads131e08_trigger_handler), (06/after.c: hid_sensor_push_data), (07/after.c: ad2s1210_trigger_handler), (08/after.c: ad4000_trigger_handler), (09/after.c: ad4030_trigger_handler), (11/after.c: ad7266_trigger_handler), (13/after.c: ad7380_trigger_handler), (15/after.c: ad7606_trigger_handler), (16/after.c: ad7768_trigger_handler), (17/after.c: ad7779_trigger_handler), (19/after.c: dln2_adc_trigger_h)
// Recall: 0.56, Precision: 0.62, Matching recall: 0.56

// ---------------------------------------------
// Final metrics (for the combined 5 rules):
// -- Edit Location --
// Recall: 1.00, Precision: 1.00
// -- Node Change --
// Recall: 0.93, Precision: 0.98
// -- General --
// Functions fully changed: 18/20(90%)

/*
Functions where the patch applied partially:
 - 00/before.c: irsd200_trigger_handler
*/
/*
Functions where the patch produced incorrect changes:
 - 04/before.c: iio_simple_dummy_trigger_h
*/

// ---------------------------------------------
