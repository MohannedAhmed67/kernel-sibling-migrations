// Migration "pci_dma_wrappers": replace the legacy pci_* DMA wrappers
// (include/linux/pci-dma-compat.h) with the generic dma_* API on &pdev->dev.
//
// Observed in training:
//   pci_set_dma_mask + pci_set_consistent_dma_mask  -> dma_set_mask_and_coherent
//   pci_set_dma_mask (alone)                        -> dma_set_mask
//   pci_alloc_consistent / pci_zalloc_consistent    -> dma_alloc_coherent(..., GFP_KERNEL)
//   pci_free_consistent                             -> dma_free_coherent
//   pci_map_page / pci_map_single / pci_unmap_single,
//   pci_dma_mapping_error, pci_dma_sync_sg_for_cpu  -> dma_* equivalents
//   PCI_DMA_TODEVICE / PCI_DMA_FROMDEVICE (in converted calls)
//                                                   -> DMA_TO_DEVICE / DMA_FROM_DEVICE

// ---------------------------------------------------------------------------
// 1. Mask setting: merge pci_set_dma_mask + pci_set_consistent_dma_mask
// ---------------------------------------------------------------------------

// 1a. "64-bit, fall back to 32-bit" idiom with the coherent mask set
//     afterwards in each branch and a shared error check.
@mask_fallback@
expression E, P, M1, M2;
statement S, S2;
@@
- E = pci_set_dma_mask(P, M1);
+ E = dma_set_mask_and_coherent(&P->dev, M1);
  if (E) {
  ...
- E = pci_set_dma_mask(P, M2);
+ E = dma_set_mask_and_coherent(&P->dev, M2);
  if (E) S
- E = pci_set_consistent_dma_mask(P, M2);
  }
- else E = pci_set_consistent_dma_mask(P, M1);
- if (E) S2

// 1b. Two sequential calls, each with its own error check: keep the first
//     check, drop the second call and its check.
@mask_seq@
expression E, P, M;
statement S1, S2;
@@
- E = pci_set_dma_mask(P, M);
+ E = dma_set_mask_and_coherent(&P->dev, M);
  if (<+... E ...+>) S1
- E = pci_set_consistent_dma_mask(P, M);
- if (<+... E ...+>) S2

// 1c. Both calls combined in one condition with ||.
@mask_or@
expression P, M;
@@
(
- pci_set_dma_mask(P, M) < 0 || pci_set_consistent_dma_mask(P, M) < 0
+ dma_set_mask_and_coherent(&P->dev, M) < 0
|
- pci_set_dma_mask(P, M) || pci_set_consistent_dma_mask(P, M)
+ dma_set_mask_and_coherent(&P->dev, M)
)

// 1d. Remaining stand-alone streaming mask setting.
@mask_only@
expression P, M;
@@
- pci_set_dma_mask(P, M)
+ dma_set_mask(&P->dev, M)

// ---------------------------------------------------------------------------
// 2. Coherent allocations
// ---------------------------------------------------------------------------
@coherent@
expression P, S, C, D;
@@
(
- pci_alloc_consistent(P, S, D)
+ dma_alloc_coherent(&P->dev, S, D, GFP_KERNEL)
|
- pci_zalloc_consistent(P, S, D)
+ dma_alloc_coherent(&P->dev, S, D, GFP_KERNEL)
|
- pci_free_consistent(P, S, C, D)
+ dma_free_coherent(&P->dev, S, C, D)
)

// ---------------------------------------------------------------------------
// 3. Streaming mappings
// ---------------------------------------------------------------------------
@streaming@
expression P, A, PG, O, S, DIR, SG, N;
@@
(
- pci_map_page(P, PG, O, S, DIR)
+ dma_map_page(&P->dev, PG, O, S, DIR)
|
- pci_map_single(P, A, S, DIR)
+ dma_map_single(&P->dev, A, S, DIR)
|
- pci_unmap_single(P, A, S, DIR)
+ dma_unmap_single(&P->dev, A, S, DIR)
|
- pci_dma_mapping_error(P, A)
+ dma_mapping_error(&P->dev, A)
|
- pci_dma_sync_sg_for_cpu(P, SG, N, DIR)
+ dma_sync_sg_for_cpu(&P->dev, SG, N, DIR)
)

// ---------------------------------------------------------------------------
// 4. Direction constants in the direction argument of the converted calls
// ---------------------------------------------------------------------------
@direction@
expression D, A, B, C;
@@
(
  dma_map_single(D, A, B, <+...
(
- PCI_DMA_TODEVICE
+ DMA_TO_DEVICE
|
- PCI_DMA_FROMDEVICE
+ DMA_FROM_DEVICE
)
  ...+>)
|
  dma_unmap_single(D, A, B, <+...
(
- PCI_DMA_TODEVICE
+ DMA_TO_DEVICE
|
- PCI_DMA_FROMDEVICE
+ DMA_FROM_DEVICE
)
  ...+>)
|
  dma_sync_sg_for_cpu(D, A, B, <+...
(
- PCI_DMA_TODEVICE
+ DMA_TO_DEVICE
|
- PCI_DMA_FROMDEVICE
+ DMA_FROM_DEVICE
)
  ...+>)
|
  dma_map_page(D, A, B, C, <+...
(
- PCI_DMA_TODEVICE
+ DMA_TO_DEVICE
|
- PCI_DMA_FROMDEVICE
+ DMA_FROM_DEVICE
)
  ...+>)
)
