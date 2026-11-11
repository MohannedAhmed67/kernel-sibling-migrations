// Composed by scripts/gcg_compose.py from qwen2.5-coder_7b (leaf_g_r3_s1) leaf rules; tasks L02 L03 L07 L09
@@
expression pdev, NUM, ID2, ID3;
@@
- pci_alloc_consistent(pdev, NUM, &ID2)
+ dma_alloc_coherent(&pdev->dev, NUM, &ID2, GFP_KERNEL)

@@
expression ID1, NUM;
identifier ID2;
@@
- err = pci_set_dma_mask(ID1, ID2(NUM));
+ err = dma_set_mask_and_coherent(&ID1->dev, ID2(NUM));

@@
expression ID1;
identifier ID2, ID3, ID4, ID5, ID6;
@@
- pci_dma_sync_sg_for_cpu ( ID1 -> ID2 -> ID3 , ID1 -> ID4 . ID5 , ID1 -> ID4 . ID6 , PCI_DMA_FROMDEVICE )
+ dma_sync_sg_for_cpu ( & ID1 -> ID2 -> ID3 -> ID2 , ID1 -> ID4 . ID5 , ID1 -> ID4 . ID6 , DMA_FROM_DEVICE )

@@
expression ID1, ID3, ID4, ID5;
identifier ID2;
@@
- pci_unmap_single ( ID1 -> ID2 , ID3 , ID4 , ID5 ? PCI_DMA_TODEVICE : PCI_DMA_FROMDEVICE )
+ dma_unmap_single ( & ID1 -> ID2 -> dev , ID3 , ID4 , ID5 ? DMA_TO_DEVICE : DMA_FROM_DEVICE )
