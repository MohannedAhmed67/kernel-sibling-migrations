@@
expression E0, E1, E2, E3, E4;
@@
- E0 = devm_kmemdup(E1, E2, E3 * sizeof(*E4), GFP_KERNEL); 
+ E0 = devm_kmemdup_array(E1, E2, E3, sizeof(*E2), GFP_KERNEL); 
// Infered from: (06/{before.c,after.c}: sc27xx_fgu_hw_init), (05/{before.c,after.c}: chv_pinctrl_probe), (04/{before.c,after.c}: sparse_keymap_setup), (00/{before.c,after.c}: pxa2xx_build_functions), (00/{before.c,after.c}: pxa2xx_build_groups)
// Recall: 0.56, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1, E2, E3;
@@
- E0 = devm_kmemdup(E1, E2, sizeof(E0[0]) * E3, GFP_KERNEL); 
+ E0 = devm_kmemdup_array(E1, E2, E3, sizeof(*E2), GFP_KERNEL); 
// Infered from: (02/{before.c,after.c}: xadc_parse_dt)
// Recall: 0.11, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1;
@@
- E0->codes = devm_kmemdup(&E1->dev, micro_keycodes,  E0->input->keycodesize * E0->input->keycodemax,  GFP_KERNEL); 
+ E0->codes = devm_kmemdup_array(&E1->dev, micro_keycodes,  E0->input->keycodemax, E0->input->keycodesize,  GFP_KERNEL); 
// Infered from: (03/{before.c,after.c}: micro_key_probe)
// Recall: 0.11, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
identifier I0;
expression E1, E2, E3;
@@
- size_t I0; 
  ...
- I0 = size_mul(sizeof(*E1), E2->nfamilies); 
- E1 = devm_kmemdup(E3, E2->families, I0, GFP_KERNEL); 
+ E1 = devm_kmemdup_array(E3, E2->families, E2->nfamilies,  sizeof(*E2->families), GFP_KERNEL); 
// Infered from: (01/{before.c,after.c}: tng_pinctrl_probe)
// Recall: 0.22, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
// Final metrics (for the combined 4 rules):
// -- Edit Location --
// Recall: 1.00, Precision: 1.00
// -- Node Change --
// Recall: 1.00, Precision: 1.00
// -- General --
// Functions fully changed: 8/8(100%)


// ---------------------------------------------
