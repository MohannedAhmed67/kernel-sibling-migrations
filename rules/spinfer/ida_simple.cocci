@@
expression E0, E1;
@@
- E0 = ida_simple_get(&E1->halloc, 1, 0, GFP_KERNEL); 
+ E0 = ida_alloc_min(&E1->halloc, 1, GFP_KERNEL); 
// Infered from: (02/{before.c,after.c}: mlx5_fpga_ipsec_create_sa_ctx)
// Recall: 0.01, Precision: 1.00, Matching recall: 0.50

// ---------------------------------------------
@@
expression E0, E1;
@@
- E0 = ida_simple_get(&cntlid_ida, E1->cntlid_min, E1->cntlid_max, GFP_KERNEL); 
+ E0 = ida_alloc_range(&cntlid_ida, E1->cntlid_min, E1->cntlid_max, GFP_KERNEL); 
// Infered from: (08/{before.c,after.c}: nvmet_alloc_ctrl)
// Recall: 0.01, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1;
@@
- E0 = ida_simple_get(&E1->tun.mac_off_ids, 0, NFP_MAX_MAC_INDEX, GFP_KERNEL); 
+ E0 = ida_alloc_max(&E1->tun.mac_off_ids, NFP_MAX_MAC_INDEX, GFP_KERNEL); 
// Infered from: (14/{before.c,after.c}: nfp_tunnel_add_shared_mac)
// Recall: 0.01, Precision: 1.00, Matching recall: 0.50

// ---------------------------------------------
@@
expression E0;
@@
- E0 = ida_simple_get(&phy_fixed_ida, 0, PHY_MAX_ADDR, GFP_KERNEL); 
+ E0 = ida_alloc_max(&phy_fixed_ida, PHY_MAX_ADDR - 1, GFP_KERNEL); 
// Infered from: (18/{before.c,after.c}: __fixed_phy_register)
// Recall: 0.01, Precision: 1.00, Matching recall: 0.50

// ---------------------------------------------
@@
expression E0, E1;
@@
- mutex_lock(&ida_lock); 
- ida_simple_remove(&E0, E1); 
- mutex_unlock(&ida_lock); 
+ ida_free(&E0, E1); 
// Infered from: (07/{before.c,after.c}: rnbd_clt_put_dev)
// Recall: 0.03, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E0, E1;
@@
- ida_simple_remove(&E0, E1); 
+ ida_free(&E0, E1); 
// Infered from: (19/{before.c,after.c}: unregister_virtio_device), (18/{before.c,after.c}: fixed_phy_del), (18/{before.c,after.c}: __fixed_phy_register), (17/{before.c,after.c}: aem_delete), (16/{before.c,after.c}: hwmon_device_unregister), (15/{before.c,after.c}: nouveau_backlight_init), (15/{before.c,after.c}: nouveau_backlight_fini), (14/{before.c,after.c}: nfp_tunnel_add_shared_mac), (14/{before.c,after.c}: nfp_tunnel_del_shared_mac), (14/{before.c,after.c}: nfp_tunnel_del_shared_mac), (13/{before.c,after.c}: nvme_free_ns_head), (13/{before.c,after.c}: nvme_release_subsystem), (13/{before.c,after.c}: nvme_cdev_rel), (13/{before.c,after.c}: nvme_free_ctrl), (12/{before.c,after.c}: nvmet_rdma_free_queue), (11/{before.c,after.c}: nvmet_fc_target_assoc_free), (11/{before.c,after.c}: nvmet_fc_free_tgtport), (10/{before.c,after.c}: nvmet_tcp_release_queue_work), (09/{before.c,after.c}: nvme_fc_free_lport), (09/{before.c,after.c}: nvme_fc_free_rport), (09/{before.c,after.c}: nvme_fc_ctrl_free), (08/{before.c,after.c}: nvmet_ctrl_free), (06/{before.c,after.c}: acpi_device_del), (05/{before.c,after.c}: alcor_pci_remove), (04/{before.c,after.c}: mlx5_core_reserved_gid_free), (03/{before.c,after.c}: del_sw_fte), (02/{before.c,after.c}: mlx5_fpga_ipsec_create_sa_ctx), (02/{before.c,after.c}: mlx5_fpga_ipsec_release_sa_ctx), (00/{before.c,after.c}: gpio_exar_remove)
// False positives: (01/after.c: __vdpa_alloc_device), (01/after.c: vdpa_release_dev)
// Recall: 0.57, Precision: 0.96, Matching recall: 0.69

// ---------------------------------------------
@@
expression E0;
@@
- mutex_lock(&ida_lock); 
- E0 = ida_simple_get(&index_ida, 0, 1 << (MINORBITS - RNBD_PART_BITS),  GFP_KERNEL); 
- mutex_unlock(&ida_lock); 
+ E0 = ida_alloc_max(&index_ida, 1 << (MINORBITS - RNBD_PART_BITS), GFP_KERNEL); 
// Infered from: (07/{before.c,after.c}: init_dev)
// Recall: 0.03, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
expression E2, E0, E1;
@@
- E0 = ida_simple_get(E1, 0, E2, GFP_KERNEL); 
+ E0 = ida_alloc(E1, GFP_KERNEL); 
// Infered from: (13/{before.c,after.c}: nvme_cdev_add), (09/{before.c,after.c}: nvme_fc_register_remoteport), (06/{before.c,after.c}: acpi_device_set_name), (05/{before.c,after.c}: alcor_pci_probe), (01/{before.c,after.c}: __vdpa_alloc_device)
// False positives: (03/after.c: insert_fte), (07/after.c: init_dev), (14/after.c: nfp_tunnel_add_shared_mac), (18/after.c: __fixed_phy_register)
// Recall: 0.25, Precision: 0.90, Matching recall: 0.48

// ---------------------------------------------
@@
identifier I0;
expression E1, E2;
@@
- int I0 = E1->roce.reserved_gids.start + E1->roce.reserved_gids.count; 
+ int I0 = E1->roce.reserved_gids.start + E1->roce.reserved_gids.count - 1; 
  ...
- E2 = ida_simple_get(&E1->roce.reserved_gids.ida,  E1->roce.reserved_gids.start, I0, GFP_KERNEL); 
+ E2 = ida_alloc_range(&E1->roce.reserved_gids.ida,  E1->roce.reserved_gids.start, I0, GFP_KERNEL); 
// Infered from: (04/{before.c,after.c}: mlx5_core_reserved_gid_alloc)
// Recall: 0.03, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
@@
identifier I0;
@@
- const  int I0 = ida_simple_get(&bl_ida, 0, 0, GFP_KERNEL); 
- if (I0 < 0 || I0 >= 100)  
+ const  int I0 = ida_alloc_max(&bl_ida, 99, GFP_KERNEL); 
+ if (I0 < 0)  
  {
  ...
  }
// Infered from: (15/{before.c,after.c}: nouveau_get_backlight_name)
// Recall: 0.03, Precision: 1.00, Matching recall: 1.00

// ---------------------------------------------
// Final metrics (for the combined 10 rules):
// -- Edit Location --
// Recall: 0.98, Precision: 0.98
// -- Node Change --
// Recall: 0.94, Precision: 0.97
// -- General --
// Functions fully changed: 48/54(88%)

/*
Functions where the patch applied partially:
 - 05/before.c: alcor_pci_probe
 - 13/before.c: nvme_alloc_ns_head
*/
/*
Functions where the patch did not apply:
 - 07/before.c: 
*/
/*
Functions where the patch produced incorrect changes:
 - 01/before.c: __vdpa_alloc_device
 - 03/before.c: insert_fte
 - 01/before.c: vdpa_release_dev
*/

// ---------------------------------------------
