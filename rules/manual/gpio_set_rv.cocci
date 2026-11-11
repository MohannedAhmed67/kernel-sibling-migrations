// gpio_set_rv: convert void gpio_chip .set/.set_multiple callbacks to the
// value-returning .set_rv/.set_multiple_rv callbacks (int, 0 or -errno).
// Only setters that are defined in the file with the old signature and are
// registered as .set/.set_multiple are touched.  In the setter body a final
// status-returning call is returned, "ret = x(); if (ret) dev_err(...);" is
// replaced by "return x();", "return;" becomes "return 0;" and a trailing
// "return 0;" is added where control falls off the end.  Callers of the
// setter are left alone.
#spatch --max-width 80

@initialize:python@
@@
SET = set()     # functions registered as .set
CONV = set()    # .set setters converted to int
CONVM = set()   # .set_multiple setters converted to int
INTF = set()    # callees known to return an int status
RETS = set()    # status variables made redundant
ENDRET = set()  # int functions whose every path ends in a return

@script:python reset@
@@
SET.clear(); CONV.clear(); CONVM.clear(); INTF.clear(); RETS.clear(); ENDRET.clear()

// ---- 1. Setters registered with a gpio_chip ------------------------------
@reg1@
identifier f, x;
type T;
@@
(
T x = { ..., .set = f, ...};
|
T x = { ..., .set_multiple = f, ...};
)

@reg2@
identifier f, x, fld;
type T;
@@
(
T x = { ..., .fld = { ..., .set = f, ...}, ...};
|
T x = { ..., .fld = { ..., .set_multiple = f, ...}, ...};
)

@reg3@
identifier f;
expression E;
@@
(
E.set = f
|
E->set = f
|
E.set_multiple = f
|
E->set_multiple = f
)

@script:python@
f << reg1.f;
@@
SET.add(f)
@script:python@
f << reg2.f;
@@
SET.add(f)
@script:python@
f << reg3.f;
@@
SET.add(f)

// ---- 2. Definitions with the old gpio_chip setter signatures -------------
@cand@
identifier f, c, o, v;
position pa, pb;
@@
void f@pa(struct gpio_chip *c, unsigned int o, int v@pb) { ... }

@candm@
identifier f, c, m, b;
position pa, pb;
@@
void f@pa(struct gpio_chip *c, unsigned long *m, unsigned long *b@pb) { ... }

// nf: prototype on one line (only the return type changes);
// nf2: prototype wrapped over several lines (re-flowed, as the humans did)
@script:python cv@
f << cand.f;
pa << cand.pa;
pb << cand.pb;
nf;
nf2;
@@
none = "__gpio_set_rv_none__"
one = f in SET and pa[0].line == pb[0].line
two = f in SET and pa[0].line != pb[0].line
if f in SET:
    CONV.add(f)
coccinelle.nf = cocci.make_ident(f if one else none)
coccinelle.nf2 = cocci.make_ident(f if two else none)

@script:python cvm@
f << candm.f;
pa << candm.pa;
pb << candm.pb;
nf;
nf2;
@@
none = "__gpio_set_rv_none__"
one = f in SET and pa[0].line == pb[0].line
two = f in SET and pa[0].line != pb[0].line
if f in SET:
    CONVM.add(f)
coccinelle.nf = cocci.make_ident(f if one else none)
coccinelle.nf2 = cocci.make_ident(f if two else none)

@sfn@
identifier cv.nf, c, o, v;
@@
- void
+ int
  nf(struct gpio_chip *c, unsigned int o, int v) { ... }

@sfn2@
identifier cv.nf2, c, o, v;
@@
- void nf2(struct gpio_chip *c, unsigned int o, int v)
+ int nf2(struct gpio_chip *c, unsigned int o, int v)
  { ... }

@sfnm@
identifier cvm.nf, c, m, b;
@@
- void
+ int
  nf(struct gpio_chip *c, unsigned long *m, unsigned long *b) { ... }

@sfnm2@
identifier cvm.nf2, c, m, b;
@@
- void nf2(struct gpio_chip *c, unsigned long *m, unsigned long *b)
+ int nf2(struct gpio_chip *c, unsigned long *m, unsigned long *b)
  { ... }

// forward declarations
@@
identifier f : script:python() { f in CONV or f in CONVM };
@@
- void
+ int
  f(...);

// ---- 3. Callees known to return an int status ----------------------------
@ri1@
identifier g;
@@
int g(...) { ... }

@ri2@
identifier g;
@@
return g(...);

@ri3@
identifier g;
identifier r =~ "^(ret|rc|err|error|rv|res|status)$";
@@
r = g(...)

@script:python@
g << ri1.g;
@@
INTF.add(g)
@script:python@
g << ri2.g;
@@
INTF.add(g)
@script:python@
g << ri3.g;
@@
INTF.add(g)

@initialize:python@
@@
import re
KNOWN = re.compile(r"^(regmap_(update_bits|write|write_bits|set_bits|clear_bits|assign_bits|field_write|field_update_bits|update_bits_base)|i2c_smbus_write_(byte|byte_data|word_data)|spi_write|spi_write_then_read)$")
# value-returning accessors (e.g. a posting read "readl(reg);") are not statuses
READISH = re.compile(r"(read|get|^in[bwl](_p)?$)")
def isint(g):
    if READISH.search(g) and KNOWN.match(g) is None:
        return False
    return g in INTF or KNOWN.match(g) is not None
def _text_at(p):
    try:
        with open(p[0].file) as fh:
            line = fh.read().split(chr(10))[int(p[0].line) - 1]
        return line[int(p[0].column):]
    except Exception:
        return ""
def explicit_return(p):
    return _text_at(p).startswith("return")
def bare_unsigned(p):
    return re.match(r"unsigned\s+(?!int\b)\w", _text_at(p)) is not None
LOGF = re.compile(r"^(dev_(err|warn|info|dbg|notice)|pr_(err|warn|info|debug|notice)|dev_(err|warn)_ratelimited|netdev_(err|warn))$")

// ---- 4. Setter bodies -----------------------------------------------------
// "if (c) ret = a(); else ret = b(); if (ret) log();" -> "if (c) return a(); return b();"
@lg1@
identifier f : script:python() { f in CONV or f in CONVM };
identifier ret;
identifier g1 : script:python() { isint(g1) };
identifier g2 : script:python() { isint(g2) };
identifier lf : script:python() { LOGF.match(lf) is not None };
expression list es1, es2, ls;
expression e;
@@
int f(...) {
  ...
- if (e) ret = g1(es1); else ret = g2(es2);
- if (\(ret\|ret < 0\)) lf(ls);
+ if (e)
+	return g1(es1);
+ return g2(es2);
}

// "ret = a(); if (ret) log();" at the end -> "return a();"
@lg2@
identifier f : script:python() { f in CONV or f in CONVM };
identifier ret;
identifier g : script:python() { isint(g) };
identifier lf : script:python() { LOGF.match(lf) is not None };
expression list es, ls;
@@
int f(...) {
  ...
- ret = g(es);
- if (\(ret\|ret < 0\)) lf(ls);
+ return g(es);
}

// drop the status variable if it became unused
@script:python@
r1 << lg1.ret;
@@
RETS.add(r1)
@script:python@
r2 << lg2.ret;
@@
RETS.add(r2)

@unused@
identifier f : script:python() { f in CONV or f in CONVM };
identifier ret : script:python() { ret in RETS };
type T;
constant C;
@@
int f(...) {
  ... when != ret
(
- T ret;
|
- T ret = C;
)
  ... when != ret
}

// "if (c) a(); else b();" at the end -> "if (c) return a(); return b();"
@ie@
identifier f : script:python() { f in CONV or f in CONVM };
identifier g1 : script:python() { isint(g1) };
identifier g2 : script:python() { isint(g2) };
expression list es1, es2;
expression e;
@@
int f(...) {
  ...
- if (e) g1(es1); else g2(es2);
+ if (e)
+	return g1(es1);
+ return g2(es2);
}

// final call returning a status -> return it
@tl@
identifier f : script:python() { f in CONV or f in CONVM };
identifier g : script:python() { isint(g) };
expression list es;
@@
int f(...) {
  ...
- g(es);
+ return g(es);
}

// bare "return;" -> "return 0;" (explicit ones only, not the implicit
// return at the closing brace)
@r0@
identifier f : script:python() { f in CONV or f in CONVM };
position p : script:python() { explicit_return(p) };
@@
int f(...) {
  <...
- return@p;
+ return 0;
  ...>
}

// falling off the end -> explicit "return 0;"
@endret@
identifier fe;
expression E;
@@
int fe(...) { ... return E; }

@script:python@
fe << endret.fe;
@@
ENDRET.add(fe)

@e0@
identifier f : script:python() { (f in CONV or f in CONVM) and f not in ENDRET };
@@
int f(...) {
  ...
+
+ return 0;
}

// ---- 5. Switch the gpio_chip callback fields -----------------------------
@@
identifier f : script:python() { f in CONV };
identifier x;
type T;
@@
T x = { ..., .
- set
+ set_rv
  = f, ...};

@@
identifier f : script:python() { f in CONV };
identifier x, fld;
type T;
@@
T x = { ..., .fld = { ..., .
- set
+ set_rv
  = f, ...}, ...};

@@
identifier f : script:python() { f in CONV };
expression E;
@@
(
  E.
- set
+ set_rv
  = f
|
  E->
- set
+ set_rv
  = f
)

@@
identifier f : script:python() { f in CONVM };
identifier x;
type T;
@@
T x = { ..., .
- set_multiple
+ set_multiple_rv
  = f, ...};

@@
identifier f : script:python() { f in CONVM };
identifier x, fld;
type T;
@@
T x = { ..., .fld = { ..., .
- set_multiple
+ set_multiple_rv
  = f, ...}, ...};

@@
identifier f : script:python() { f in CONVM };
expression E;
@@
(
  E.
- set_multiple
+ set_multiple_rv
  = f
|
  E->
- set_multiple
+ set_multiple_rv
  = f
)

// ---- 6. Bare "unsigned" offset parameter -> "unsigned int" -----------------
@@
identifier cv.nf, sfn.c, sfn.o, sfn.v;
type T;
position p : script:python() { bare_unsigned(p) };
@@
int nf(struct gpio_chip *c,
-   T@p o
+   unsigned int o
    , int v) { ... }
