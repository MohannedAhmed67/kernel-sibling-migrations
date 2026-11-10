// Migration: platform_remove_new
// Convert a platform driver's .remove callback that always returns 0 into a
// .remove_new callback returning void:
//
//   static int foo_remove(struct platform_device *pdev)   -> static void ...
//   { ...; return 0; }                                    -> drop trailing return 0
//   .remove = foo_remove,                                 -> .remove_new = foo_remove,

// 1. Find the remove callback registered in a struct platform_driver.
@drv@
identifier d, rm;
@@
struct platform_driver d = {
	.remove = rm,
};

// 2. Exclude callbacks with an early (nested) return: converting those would
//    need "return 0;" -> "return;" rewrites, which the examples never show.
@early@
identifier drv.rm, pdev;
expression E;
statement S;
@@
int rm(struct platform_device *pdev)
{
	... when any
(
	if (E) return ...;
|
	if (E) return ...; else S
|
	if (E) S else return ...;
|
	if (E) { ... return ...; }
|
	if (E) { ... return ...; } else S
|
	if (E) S else { ... return ...; }
|
	for (...;...;...) { <+... return ...; ...+> }
|
	while (E) { <+... return ...; ...+> }
)
	... when any
}

// 3. Change the return type to void and drop the trailing "return 0;".
//    Every path must end in "return 0;", so callbacks that return an error
//    code or a variable are left untouched.
@fn depends on !early@
identifier drv.rm, pdev;
@@
- int
+ void
  rm(struct platform_device *pdev)
  {
  ...
- return 0;
  }

// 4. Switch the platform_driver field, only for converted callbacks.
//    (Coccinelle re-prints the line as ".remove_new = rm,"; upstream sometimes
//    re-aligned with tabs instead, a whitespace-only difference.)
@depends on fn@
identifier drv.d, drv.rm;
@@
struct platform_driver d = {
-	.remove = rm,
+	.remove_new = rm,
};
