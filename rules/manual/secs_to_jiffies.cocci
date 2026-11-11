// msecs_to_jiffies(<seconds> * 1000) -> secs_to_jiffies(<seconds>)
// Learned from train/: only compile-time constants (literals, UPPER_CASE macros)
// are converted when multiplied by a literal 1000; runtime values times 1000 are
// left alone. Any expression times MSEC_PER_SEC is converted.

@@
constant C;
@@
- msecs_to_jiffies(C * 1000)
+ secs_to_jiffies(C)

@@
constant C;
@@
- msecs_to_jiffies(1000 * C)
+ secs_to_jiffies(C)

@@
expression E;
@@
- msecs_to_jiffies(E * MSEC_PER_SEC)
+ secs_to_jiffies(E)
