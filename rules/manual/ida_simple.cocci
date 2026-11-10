// Migration "ida_simple": replace the deprecated ida_simple_get()/ida_simple_remove()
// wrappers with ida_alloc*()/ida_free().
//
// ida_simple_get(ida, start, end, gfp) allocates in [start, end) (end == 0 means
// "no upper limit"), whereas ida_alloc_max()/ida_alloc_range() take an INCLUSIVE
// maximum, so a non-zero end becomes "end - 1".
//
//   ida_simple_get(ida, 0, 0, gfp)  -> ida_alloc(ida, gfp)
//   ida_simple_get(ida, S, 0, gfp)  -> ida_alloc_min(ida, S, gfp)
//   ida_simple_get(ida, 0, E, gfp)  -> ida_alloc_max(ida, E - 1, gfp)
//   ida_simple_get(ida, S, E, gfp)  -> ida_alloc_range(ida, S, E - 1, gfp)
//   ida_simple_remove(ida, id)      -> ida_free(ida, id)

// 1. No limits at all, or only a lower limit.
@ida_get_nomax@
expression ida, gfp, S;
@@
(
- ida_simple_get(ida, 0, 0, gfp)
+ ida_alloc(ida, gfp)
|
- ida_simple_get(ida, S, 0, gfp)
+ ida_alloc_min(ida, S, gfp)
)

// 2. Upper limit given as an expression whose top-level operator binds less
//    tightly than (or as loosely as) binary '-': parenthesise before subtracting.
@ida_get_max_paren@
expression ida, gfp, S, E1, E2, E3;
binary operator b = {<<, >>, &, |, ^, &&, ||, <, >, <=, >=, ==, !=};
@@
(
- ida_simple_get(ida, 0, E1 b E2, gfp)
+ ida_alloc_max(ida, (E1 b E2) - 1, gfp)
|
- ida_simple_get(ida, 0, E1 ? E2 : E3, gfp)
+ ida_alloc_max(ida, (E1 ? E2 : E3) - 1, gfp)
|
- ida_simple_get(ida, S, E1 b E2, gfp)
+ ida_alloc_range(ida, S, (E1 b E2) - 1, gfp)
|
- ida_simple_get(ida, S, E1 ? E2 : E3, gfp)
+ ida_alloc_range(ida, S, (E1 ? E2 : E3) - 1, gfp)
)

// 3. Remaining upper limits (identifiers, constants, macros, field accesses,
//    calls, sums/differences, ...): plain "E - 1".
@ida_get_max@
expression ida, gfp, S, E;
@@
(
- ida_simple_get(ida, 0, E, gfp)
+ ida_alloc_max(ida, E - 1, gfp)
|
- ida_simple_get(ida, S, E, gfp)
+ ida_alloc_range(ida, S, E - 1, gfp)
)

// 4. Release.
@ida_remove@
expression ida, id;
@@
- ida_simple_remove(ida, id)
+ ida_free(ida, id)
