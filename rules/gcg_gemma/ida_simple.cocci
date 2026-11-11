// Composed by scripts/gcg_compose.py from gemma3_4b (leaf_g_r3_s1) leaf rules; tasks L00 L01 L03
@@
expression id, index, NUM, STR;
@@
- ida_simple_remove ( & id , index );
+ ida_free ( & id , index );
  ...

@@
expression ID1, ID2, NUM, STR;
@@
- ida_simple_get ( & ID1 , 0 , NUM , GFP_KERNEL )
+ ida_alloc ( & ID1 , GFP_KERNEL )
  ...

@@
identifier ID2;
expression ID1, NUM;
@@
- ida_simple_get ( & ID1 -> ID2 , NUM , NUM , ID2 )
+ ida_alloc ( & ID1 -> ID2 , ID2 )
  ...

@@

@@
- ida_simple_get ( instance_ida , 0 , ACPI_MAX_DEVICE_INSTANCES , GFP_KERNEL )
+ ida_alloc ( instance_ida , GFP_KERNEL )
  ...

@@
expression E, SIZE, FLAGS;
@@
- E = ida_simple_get ( & fipsec -> halloc , 1 , 0 , GFP_KERNEL );
+ E = ida_alloc_min ( & fipsec -> halloc , 1 , GFP_KERNEL );
  ...

@@

@@
- E = ida_simple_get ( & ctrl -> subsys -> ns_ida , 1 , 0 , GFP_KERNEL );
+ E = ida_alloc_min ( & ctrl -> subsys -> ns_ida , 1 , GFP_KERNEL );
  ...

@@
identifier ID2, ID3;
expression ID1, ID4, NUM;
@@
- E = ida_simple_get ( & ID1 -> ID2 -> ID3 , NUM , NUM , ID4 );
+ E = ida_alloc_min ( & ID1 -> ID2 -> ID3 , NUM , ID4 );
  ...
