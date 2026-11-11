// Composed by scripts/gcg_compose.py from llama3.1_8b (leaf_g_r3_s1) leaf rules; tasks L02 L09
@@
identifier pdev, ID2, ret, err;
expression NUM;
@@
- pci_set_dma_mask(pdev, ID2(NUM))
+ dma_set_mask_and_coherent(&pdev->dev, ID2(NUM))

@@
identifier ID2;
expression NUM;
@@
- ret = pci_set_dma_mask(pdev, ID2(NUM))
+ ret = dma_set_mask_and_coherent(&pdev->dev, ID2(NUM))

@@
identifier ID2;
expression NUM;
@@
- err = pci_set_dma_mask(pdev, ID2(NUM))
+ err = dma_set_mask_and_coherent(&pdev->dev, ID2(NUM))

@@
identifier ID1, ID2;
expression dma_addr, size, wr;
@@
- pci_unmap_single(ID1->ID2, dma_addr, size, wr ? PCI_DMA_TODEVICE : PCI_DMA_FROMDEVICE)
+ dma_unmap_single(&ID1->ID2->dev, dma_addr, size, wr ? DMA_TO_DEVICE : DMA_FROM_DEVICE)
