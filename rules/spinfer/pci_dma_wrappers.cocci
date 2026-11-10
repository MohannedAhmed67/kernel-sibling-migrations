@@
identifier I3, I4;
expression E0, E1, E2;
@@
- pci_free_consistent(E0, E1, E2->I3, E2->I4); 
+ dma_free_coherent(&E0->dev, E1, E2->I3, E2->I4); 
// Infered from: (19/{before.c,after.c}: av7110_detach), (18/{before.c,after.c}: solo_enc_free), (18/{before.c,after.c}: solo_enc_v4l2_init), (18/{before.c,after.c}: solo_enc_v4l2_exit), (16/{before.c,after.c}: snd_solo_pcm_close), (14/{before.c,after.c}: dm1105_dma_unmap), (12/{before.c,after.c}: btcx_riscmem_free), (11/{before.c,after.c}: bt878_mem_free), (11/{before.c,after.c}: bt878_mem_free), (10/{before.c,after.c}: flexcop_dma_free), (02/{before.c,after.c}: pch_gbe_free_tx_resources), (02/{before.c,after.c}: pch_gbe_free_rx_resources), (02/{before.c,after.c}: pch_gbe_down)
// Recall: 0.23, Precision: 1.00, Matching recall: 0.83

// ---------------------------------------------
@@
identifier I1 = {pci_alloc_consistent ,pci_zalloc_consistent };
expression E0, E2, E3, E4;
@@
- E0 = I1(E2, E3, &E4); 
+ E0 = dma_alloc_coherent(&E2->dev, E3, &E4, GFP_KERNEL); 
// Infered from: (18/{before.c,after.c}: solo_enc_v4l2_init), (16/{before.c,after.c}: snd_solo_pcm_open), (14/{before.c,after.c}: dm1105_dma_map), (12/{before.c,after.c}: btcx_riscmem_alloc), (11/{before.c,after.c}: bt878_mem_alloc), (10/{before.c,after.c}: flexcop_dma_allocate)
// Recall: 0.14, Precision: 1.00, Matching recall: 0.75

// ---------------------------------------------
@@
expression E0, E1;
@@
- E0 = pci_set_dma_mask(E1, DMA_BIT_MASK(32)); 
+ E0 = dma_set_mask(&E1->dev, DMA_BIT_MASK(32)); 
// Infered from: (14/{before.c,after.c}: dm1105_probe)
// False positives: (01/after.c: qib_pcie_init)
// Recall: 0.02, Precision: 0.75, Matching recall: 0.25

// ---------------------------------------------
@@
expression E0;
@@
- if (pci_set_dma_mask(E0, DMA_BIT_MASK(32)))  
+ if (dma_set_mask(&E0->dev, DMA_BIT_MASK(32)))  
  {
  ...
  }
// Infered from: (13/{before.c,after.c}: bttv_probe)
// Recall: 0.02, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0;
@@
- if (pci_set_dma_mask(E0, DMA_BIT_MASK(28)) < 0 || pci_set_consistent_dma_mask(  E0, DMA_BIT_MASK(28)) < 0)  
+ if (dma_set_mask_and_coherent(&E0->dev, DMA_BIT_MASK(28)) < 0)  
  {
  ...
  }
// Infered from: (00/{before.c,after.c}: snd_emu10k1x_create)
// Recall: 0.02, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E1, E2, E0;
@@
- E0 = pci_map_page(E1->pdev, E2, 0, PAGE_SIZE, PCI_DMA_BIDIRECTIONAL); 
- if (pci_dma_mapping_error(E1->pdev, E0))  
+ E0 = dma_map_page(&E1->pdev->dev, E2, 0, PAGE_SIZE, PCI_DMA_BIDIRECTIONAL); 
+ if (dma_mapping_error(&E1->pdev->dev, E0))  
  {
  ...
  }
// Infered from: (04/{before.c,after.c}: radeon_dummy_page_init), (03/{before.c,after.c}: amdgpu_gart_dummy_page_init)
// Recall: 0.06, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1, E2, E3;
@@
- E0 = pci_set_dma_mask(E1, DMA_BIT_MASK(48)); 
+ E0 = dma_set_mask_and_coherent(&E1->dev, DMA_BIT_MASK(48)); 
  ...
- E0 = pci_set_consistent_dma_mask(E1, DMA_BIT_MASK(48)); 
- if (E0)  
- {
- dev_err(E2, E3); 
  ...
- }
// Infered from: (09/{before.c,after.c}: cptvf_probe), (08/{before.c,after.c}: cpt_probe), (07/{before.c,after.c}: otx_cptvf_probe), (06/{before.c,after.c}: otx_cpt_probe), (05/{before.c,after.c}: zip_probe)
// Recall: 0.20, Precision: 1.00, Matching recall: 0.62

// ---------------------------------------------
@@
expression E0, E1;
@@
- E0 = pci_set_dma_mask(E1, DMA_BIT_MASK(64)); 
+ E0 = dma_set_mask_and_coherent(&E1->dev, DMA_BIT_MASK(64)); 
  ...
- if (E0)  
- {
- qib_early_err(&E1->dev, "Unable to set DMA consistent mask: %d\n", E0); 
- goto  bail; 
- }
// Infered from: (01/{before.c,after.c}: qib_pcie_init)
// Recall: 0.04, Precision: 1.00, Matching recall: 0.50

// ---------------------------------------------
@@
expression E0, E1, E2;
@@
- E0 = pci_set_dma_mask(E1, DMA_BIT_MASK(E2)); 
+ E0 = dma_set_mask_and_coherent(&E1->dev, DMA_BIT_MASK(E2)); 
  ...
- E0 = pci_set_consistent_dma_mask(E1, DMA_BIT_MASK(E2)); 
- if (E0)  
- {
- dev_err(&E1->dev, "err_pci_set_consistent_dma_mask failed %d\n", E0); 
- return E0; 
- }
// Infered from: (15/{before.c,after.c}: efa_device_init)
// Recall: 0.05, Precision: 1.00, Matching recall: 0.75

// ---------------------------------------------
@@
expression list E1;
expression E0;
@@
- E0 = pci_set_consistent_dma_mask (E1); 
// Infered from: (01/{before.c,after.c}: qib_pcie_init), (01/{before.c,after.c}: qib_pcie_init)
// Recall: 0.06, Precision: 1.00, Matching recall: 0.14

// ---------------------------------------------
@@
expression E0, E1, E2, E3, E4;
@@
- E0 = pci_map_single(E1->pdev, E2, E3,  E4 ? PCI_DMA_TODEVICE :PCI_DMA_FROMDEVICE); 
- if (pci_dma_mapping_error(E1->pdev, E0))  
+ E0 = dma_map_single(&E1->pdev->dev, E2, E3,  E4 ? DMA_TO_DEVICE :DMA_FROM_DEVICE); 
+ if (dma_mapping_error(&E1->pdev->dev, E0))  
  {
  ...
  }
  ...
- pci_unmap_single(E1->pdev, E0, E3, E4 ? PCI_DMA_TODEVICE :PCI_DMA_FROMDEVICE); 
+ dma_unmap_single(&E1->pdev->dev, E0, E3, E4 ? DMA_TO_DEVICE :DMA_FROM_DEVICE); 
// Infered from: (17/{before.c,after.c}: solo_p2m_dma)
// Recall: 0.05, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0;
@@
- pci_dma_sync_sg_for_cpu(E0->dev->pci, E0->pt.slist, E0->pt.nents,  PCI_DMA_FROMDEVICE); 
+ dma_sync_sg_for_cpu(&E0->dev->pci->dev, E0->pt.slist, E0->pt.nents,  DMA_FROM_DEVICE); 
// Infered from: (19/{before.c,after.c}: vpeirq)
// Recall: 0.02, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
// Final metrics (for the combined 12 rules):
// -- Edit Location --
// Recall: 1.00, Precision: 1.00
// -- Node Change --
// Recall: 0.85, Precision: 0.99
// -- General --
// Functions fully changed: 26/33(78%)

/*
Functions where the patch applied partially:
 - 06/before.c: otx_cpt_probe
 - 07/before.c: otx_cptvf_probe
 - 09/before.c: cptvf_probe
 - 15/before.c: efa_device_init
 - 08/before.c: cpt_probe
 - 05/before.c: zip_probe
*/
/*
Functions where the patch produced incorrect changes:
 - 01/before.c: qib_pcie_init
*/

// ---------------------------------------------
