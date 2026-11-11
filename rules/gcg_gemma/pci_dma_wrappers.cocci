// Composed by scripts/gcg_compose.py from gemma3_4b (leaf_g_r3_s1) leaf rules; tasks L00 L03
@@
expression ID1, ID2, ID6, NUM, STR;
identifier ID3, ID4, ID5;
@@
- pci_free_consistent ( ID1, ID2->ID3, ID2->ID4, ID2->ID5 );
+ dma_free_coherent ( &ID1->dev, ID2->ID3, ID2->ID4, ID2->ID5 );
  ...

@@
expression E, SIZE, FLAGS;
expression ID1, ID2, ID3;
@@
- E = pci_alloc_consistent ( ID1 , ID2 , & ID3 );
+ E = dma_alloc_coherent ( & ID1 -> dev , ID2 , & ID3 , GFP_KERNEL );
  ...
