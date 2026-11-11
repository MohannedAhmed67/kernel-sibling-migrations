// Composed by scripts/gcg_compose.py from qwen2.5-coder_7b (leaf_g_r3_s1) leaf rules; tasks L00 L01 L03
@@
expression ID1, ID2;
identifier ID3;
@@
- ida_simple_remove ( & ID1 , ID2 -> ID3 )
+ ida_free ( & ID1 , ID2 -> ID3 )

@@
expression ID1, ID2;
expression NUM;
@@
- ida_simple_get(&ID1, NUM, NUM, ID2)
+ ida_alloc(&ID1, ID2)

@@
expression ID1, NUM, ID3;
identifier ID2;
@@
- ida_simple_get(&ID1->ID2, NUM, 0, ID3)
+ ida_alloc_min(&ID1->ID2, NUM, ID3)

@@
expression ID1, NUM;
identifier ID2, ID3;
expression ID4;
@@
- ida_simple_get(&ID1->ID2->ID3, NUM, 0, ID4)
+ ida_alloc_min(&ID1->ID2->ID3, NUM, ID4)
