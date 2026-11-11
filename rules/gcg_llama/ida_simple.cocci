// Composed by scripts/gcg_compose.py from llama3.1_8b (leaf_g_r3_s1) leaf rules; tasks L00 L03
@@
expression ida, id;
@@
- ida_simple_remove(&ida, id)
+ ida_free(&ida, id)

@@
identifier ID1, ID2, ID3;
constant NUM, NUM2;
@@
- ida_simple_get(&ID1->ID2, NUM, NUM2, ID3)
+ ida_alloc_min(&ID1->ID2, NUM, ID3)
