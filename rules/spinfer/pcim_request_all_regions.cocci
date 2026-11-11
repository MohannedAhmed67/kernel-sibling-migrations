@@
expression E0;
@@
- pci_release_regions(E0); 
// Infered from: (00/{before.c,after.c}: thunderx_spi_remove)
// Recall: 0.07, Precision: 1.00, Matching recall: 0.23

// ---------------------------------------------
@@
identifier I4;
expression E0, E1, E2, E3;
@@
- E0 = pci_request_regions(E1, E2); 
+ E0 = pcim_request_all_regions(E1, E2); 
  ...
- if (!E3->reg_base)  
+ if (!E3->reg_base)  
  {
- E0 = -I4; 
- goto  error; 
+ return -EINVAL; 
  }
// Infered from: (01/{before.c,after.c}: pci1xxxx_spi_probe)
// Recall: 0.11, Precision: 1.00, Matching recall: 0.56

// ---------------------------------------------
@@
expression E0, E1, E2;
@@
- E0 = pci_request_regions(E1, E2); 
+ E0 = pcim_request_all_regions(E1, E2); 
// Infered from: (17/{before.c,after.c}: snd_fm801_create), (16/{before.c,after.c}: snd_ymfpci_create), (15/{before.c,after.c}: snd_lx6464es_create), (14/{before.c,after.c}: snd_azf3328_create), (13/{before.c,after.c}: snd_rme9652_create), (12/{before.c,after.c}: snd_hdsp_create), (11/{before.c,after.c}: __oxygen_pci_probe), (09/{before.c,after.c}: snd_via82xx_create), (08/{before.c,after.c}: snd_via82xx_create), (07/{before.c,after.c}: snd_cmipci_create), (06/{before.c,after.c}: snd_rme32_create), (05/{before.c,after.c}: snd_rme96_create), (04/{before.c,after.c}: sis_chip_create), (03/{before.c,after.c}: snd_sonicvibes_create), (02/{before.c,after.c}: snd_ensoniq_create)
// False positives: (10/after.c: snd_vx222_create)
// Recall: 0.78, Precision: 0.97, Matching recall: 0.80

// ---------------------------------------------
@@
identifier I1;
expression E0;
@@
- E0 = -I1; 
- goto  error; 
+ return -ENODEV; 
// Infered from: (01/{before.c,after.c}: pci1xxxx_spi_probe), (01/{before.c,after.c}: pci1xxxx_spi_probe)
// False positives: (00/after.c: thunderx_spi_probe), (01/after.c: pci1xxxx_spi_probe), (01/after.c: pci1xxxx_spi_transfer_with_dma), (05/after.c: snd_rme96_playback_hw_params)
// Recall: 0.09, Precision: 0.25, Matching recall: 0.33

// ---------------------------------------------
// Final metrics (for the combined 4 rules):
// -- Edit Location --
// Recall: 1.00, Precision: 0.90
// -- Node Change --
// Recall: 0.96, Precision: 0.78
// -- General --
// Functions fully changed: 16/21(76%)

/*
Functions where the patch applied partially:
 - 01/before.c: pci1xxxx_spi_probe
*/
/*
Functions where the patch produced incorrect changes:
 - 10/before.c: snd_vx222_create
 - 05/before.c: snd_rme96_playback_hw_params
 - 01/before.c: pci1xxxx_spi_transfer_with_dma
 - 00/before.c: thunderx_spi_probe
*/

// ---------------------------------------------
