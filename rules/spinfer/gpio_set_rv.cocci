@@
identifier I1, I2;
expression E0;
@@
- E0->I1.set = I2; 
+ E0->I1.set_rv = I2; 
// Infered from: (16/{before.c,after.c}: crystalcove_gpio_probe), (15/{before.c,after.c}: bd71828_probe), (13/{before.c,after.c}: creg_gpio_probe), (11/{before.c,after.c}: aspeed_gpio_probe), (10/{before.c,after.c}: altera_gpio_probe), (07/{before.c,after.c}: aspeed_sgpio_probe), (06/{before.c,after.c}: amd_fch_gpio_probe), (04/{before.c,after.c}: gen_74x164_probe), (03/{before.c,after.c}: davinci_gpio_probe), (02/{before.c,after.c}: max77650_gpio_probe), (01/{before.c,after.c}: mvebu_gpio_probe), (00/{before.c,after.c}: gpio_latch_probe)
// Recall: 0.16, Precision: 1.00, Matching recall: 0.93

// ---------------------------------------------
@@
expression E0;
@@
- E0->gpio_chip.set_multiple = gen_74x164_set_multiple; 
+ E0->gpio_chip.set_multiple_rv = gen_74x164_set_multiple; 
// Infered from: (04/{before.c,after.c}: gen_74x164_probe)
// Recall: 0.01, Precision: 1.00, Matching recall: 0.50

// ---------------------------------------------
@@
expression E0, E1, E2;
@@
- creg_gpio_set(E0, E1, E2); 
- return 0; 
+ return creg_gpio_set(E0, E1, E2); 
// Infered from: (13/{before.c,after.c}: creg_gpio_dir_out)
// Recall: 0.02, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1, E2;
@@
- da9055_gpio_set(E0, E1, E2); 
- return 0; 
+ return da9055_gpio_set(E0, E1, E2); 
// Infered from: (19/{before.c,after.c}: da9055_gpio_direction_output)
// Recall: 0.02, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
// Final metrics (for the combined 4 rules):
// -- Edit Location --
// Recall: 0.31, Precision: 1.00
// -- Node Change --
// Recall: 0.21, Precision: 1.00
// -- General --
// Functions fully changed: 14/45(31%)

/*
Functions where the patch did not apply:
 - 05/before.c: 
 - 08/before.c: amd_gpio_set
 - 12/before.c: chip_gpio_set
 - 13/before.c: creg_gpio_set
 - 17/before.c: bcm_kona_gpio_set
 - 02/before.c: max77650_gpio_set_value
 - 09/before.c: 
 - 18/before.c: bd9571mwv_gpio_set
 - 16/before.c: crystalcove_gpio_set
 - 19/before.c: da9055_gpio_set
 - 00/before.c: gpio_latch_set_unlocked
 - 17/before.c: 
 - 19/before.c: 
 - 03/before.c: davinci_gpio_set
 - 04/before.c: gen_74x164_set_multiple
 - 08/before.c: 
 - 14/before.c: bd71815gpo_set
 - 00/before.c: gpio_latch_set_can_sleep
 - 04/before.c: gen_74x164_set_value
 - 12/before.c: 
 - 18/before.c: 
 - 00/before.c: gpio_latch_set
 - 05/before.c: altr_a10sr_gpio_set
 - 07/before.c: aspeed_sgpio_set
 - 10/before.c: altera_gpio_set
 - 11/before.c: aspeed_gpio_set
 - 15/before.c: bd71828_gpio_set
 - 01/before.c: mvebu_gpio_set
 - 09/before.c: arizona_gpio_set
 - 14/before.c: 
 - 06/before.c: amd_fch_gpio_set
*/

// ---------------------------------------------
