// Migration: i2c_probe_new
//
// struct i2c_driver used to take its single-argument probe callback,
// int fn(struct i2c_client *), through the transitional .probe_new member.
// After the migration the same callback is installed through .probe.
// The callback and every other initializer are left unchanged; only the
// designator name probe_new is renamed to probe.
//
// Only the field identifier is replaced (not the whole ".probe_new = fn,"
// entry), so spatch keeps the original whitespace of the line instead of
// pretty-printing it as ".probe = fn,".

@i2c_probe_new@
identifier drv;
expression fn;
@@
struct i2c_driver drv = {
	.
-	probe_new
+	probe
	= fn,
};
