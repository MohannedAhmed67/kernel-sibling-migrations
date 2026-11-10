// Migration: strlcpy -> strscpy
//
// Every training example converts a strlcpy() call whose return value is
// unused (the call is a whole expression statement) into strscpy() with
// the same three arguments, unchanged.  Calls whose return value is used
// (assigned, compared, returned) are left alone, because strscpy() returns
// a different value (-E2BIG on truncation, not the source length) and no
// training example shows such a call being converted.

@strlcpy_to_strscpy@
expression dst, src, size;
@@

- strlcpy
+ strscpy
  (dst, src, size);
