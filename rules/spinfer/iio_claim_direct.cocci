@@
expression E0, E1;
@@
- E0 = iio_device_claim_direct_mode(E1); 
- if (E0)  
+ if (!iio_device_claim_direct(E1))  
  {
  ...
  }
  ...
- iio_device_release_direct_mode(E1); 
+ iio_device_release_direct(E1); 
// Infered from: (07/{before.c,after.c}: bmi088_accel_read_raw)
// Recall: 0.53, Precision: 1.00, Matching recall: 0.72

// ---------------------------------------------
@@
expression E0, E1, E2;
@@
- E0 = iio_device_claim_direct_mode(E1); 
- if (E2)  
- {
- return E0; 
- }
  ...
- iio_device_release_direct_mode(E1); 
+ iio_device_release_direct(E1); 
// Infered from: (19/{before.c,after.c}: ad7768_read_raw), (18/{before.c,after.c}: ad799x_read_raw), (18/{before.c,after.c}: ad799x_write_event_config), (17/{before.c,after.c}: ad7791_write_raw), (16/{before.c,after.c}: ad_sigma_delta_single_conversion), (15/{before.c,after.c}: ad4030_read_raw), (15/{before.c,after.c}: ad4030_write_raw), (15/{before.c,after.c}: ad4030_reg_access), (14/{before.c,after.c}: ad7793_write_raw), (13/{before.c,after.c}: ad7192_set), (13/{before.c,after.c}: ad7192_write_raw), (12/{before.c,after.c}: ad7606_write_raw), (12/{before.c,after.c}: ad7606_write_raw), (11/{before.c,after.c}: stm32_dfsdm_write_raw), (11/{before.c,after.c}: stm32_dfsdm_write_raw), (11/{before.c,after.c}: stm32_dfsdm_read_raw), (10/{before.c,after.c}: mma8452_read_raw), (10/{before.c,after.c}: mma8452_write_raw), (09/{before.c,after.c}: kx022a_write_raw), (09/{before.c,after.c}: kx022a_read_raw), (08/{before.c,after.c}: fxls8962af_write_raw), (08/{before.c,after.c}: fxls8962af_write_raw), (08/{before.c,after.c}: fxls8962af_write_event_config), (06/{before.c,after.c}: bma180_read_raw), (04/{before.c,after.c}: adxl372_read_raw), (03/{before.c,after.c}: msa311_read_raw_data), (03/{before.c,after.c}: msa311_write_samp_freq), (02/{before.c,after.c}: shunt_resistor_store), (00/{before.c,after.c}: scd30_read_raw)
// Recall: 0.66, Precision: 1.00, Matching recall: 0.71

// ---------------------------------------------
// Final metrics (for the combined 2 rules):
// -- Edit Location --
// Recall: 0.90, Precision: 1.00
// -- Node Change --
// Recall: 0.68, Precision: 1.00
// -- General --
// Functions fully changed: 0/31(0%)

/*
Functions where the patch applied partially:
 - 10/before.c: mma8452_read_raw
 - 16/before.c: ad_sigma_delta_single_conversion
 - 09/before.c: kx022a_write_raw
 - 11/before.c: stm32_dfsdm_read_raw
 - 01/before.c: tmp006_write_raw
 - 08/before.c: fxls8962af_write_event_config
 - 10/before.c: mma8452_write_raw
 - 03/before.c: msa311_write_samp_freq
 - 04/before.c: adxl372_read_raw
 - 12/before.c: ad7606_write_raw
 - 17/before.c: ad7791_write_raw
 - 09/before.c: kx022a_read_raw
 - 14/before.c: ad7793_write_raw
 - 03/before.c: msa311_read_raw_data
 - 15/before.c: ad4030_read_raw
 - 07/before.c: bmi088_accel_read_raw
 - 11/before.c: stm32_dfsdm_write_raw
 - 13/before.c: ad7192_set
 - 15/before.c: ad4030_reg_access
 - 00/before.c: scd30_read_raw
 - 02/before.c: shunt_resistor_store
 - 13/before.c: ad7192_write_raw
 - 15/before.c: ad4030_write_raw
 - 08/before.c: fxls8962af_write_raw
 - 18/before.c: ad799x_read_raw
 - 19/before.c: ad7768_read_raw
 - 18/before.c: ad799x_write_event_config
 - 06/before.c: bma180_read_raw
*/

// ---------------------------------------------
