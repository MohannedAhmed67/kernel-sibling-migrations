// Composed by scripts/gcg_compose.py from qwen2.5-coder_7b (leaf_g_r3_s1) leaf rules; tasks L00
@@
identifier drv, fn;
@@
  struct i2c_driver drv = {
-   .probe_new = fn,
+   .probe = fn,
  };
