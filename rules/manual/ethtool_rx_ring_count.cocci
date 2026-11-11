// ethtool_rx_ring_count: move ETHTOOL_GRXRINGS handling out of .get_rxnfc
// into a dedicated .get_rx_ring_count callback, u32 (*)(struct net_device *).
// A: .get_rxnfc only answers ETHTOOL_GRXRINGS -> it becomes .get_rx_ring_count.
// B: .get_rxnfc also handles other commands -> the GRXRINGS case is removed
//    and a new .get_rx_ring_count callback is added next to it.

@initialize:python@
@@
import re

def only_uses(e, allowed, required):
    s = re.sub(r'"(\\.|[^"])*"', '', e)
    seen = set()
    for m in re.finditer(r'(->|\.)?\s*\b([A-Za-z_]\w*)\b(\s*\()?', s):
        name = m.group(2)
        if m.group(1) or m.group(3):
            continue
        if name in allowed:
            seen.add(name)
            continue
        if re.match(r'^[A-Z0-9_]+$', name):
            continue
        if name in ('int', 'u32', 'unsigned', 'u16', 'u8', 'sizeof'):
            continue
        return False
    return all(r in seen for r in required)

# Text of the new ".get_rx_ring_count = g" initializer, aligned like the
# .get_rxnfc initializer on line `line` of `path` (keeps its '=' column and
# tab/space style when the longer name still fits, else a single space).
def dcol(s):
    col = 0
    for ch in s:
        col = (int(col / 8) + 1) * 8 if ch == '\t' else col + 1
    return col

def aligned_init(path, line, g):
    plain = '.get_rx_ring_count = ' + g
    try:
        text = open(path).read().split('\n')[int(line) - 1]
    except Exception:
        return plain
    m = re.match(r'^(\s*)\.(\w+)(\s*)=', text)
    if not m:
        return plain
    lead, name, ws = m.groups()
    target = dcol(lead + '.' + name + ws)
    c0 = dcol(lead + '.get_rx_ring_count')
    if '\t' in ws:
        pad, c = '', c0
        while c < target:
            pad += '\t'
            c = (int(c / 8) + 1) * 8
        if c != target or not pad:
            pad = ' '
    else:
        pad = ' ' * (target - c0) if target - c0 >= 1 else ' '
    return '.get_rx_ring_count' + pad + '= ' + g

# name of the .set_rxnfc callback if it follows .get_rxnfc (line `line`)
# in the same initializer, else None
def set_after(path, line):
    try:
        lines = open(path).read().split('\n')
    except Exception:
        return None
    for t in lines[int(line):]:
        if re.match(r'^\s*\}\s*;', t):
            return None
        m = re.match(r'^\s*\.set_rxnfc\s*=\s*(\w+)', t)
        if m:
            return m.group(1)
    return None

def norm(s):
    return ' '.join(s.split())

# Case B: S is a dispatcher on I->cmd that handles ETHTOOL_GRXRINGS among
# other commands.  Returns the GRXRINGS value expression, or None.
def extract_case(S, I):
    s = norm(S)
    Iq = re.escape(I)
    if s.count('ETHTOOL_GRXRINGS') != 1:
        return None
    m = re.match(r'^if \( %s -> cmd == ETHTOOL_GRXRINGS \) \{ %s -> data = ([^;]+) ; return 0 ; \}$' % (Iq, Iq), s)
    if m:
        E = m.group(1)
    else:
        if not re.match(r'^switch \( %s -> cmd \) \{ ' % Iq, s):
            return None
        m = re.search(r'(?:\{|; |: ) ?case ETHTOOL_GRXRINGS : %s -> data = ([^;]+) ; (?:break ; |\w+ = 0 ; break ; |return 0 ; )(case |default :)' % Iq, s)
        if not m:
            return None
        E = m.group(1)
        others = re.findall(r'\bcase (?!ETHTOOL_GRXRINGS\b)', s)
        if not others:
            return None
        pre = s[:s.index("case ETHTOOL_GRXRINGS")].rstrip()
        if not (pre == "switch ( %s -> cmd ) {" % I or pre.endswith("break ;")
                or re.search(r"\b(return|goto)\b[^;{}]* ;$", pre)):
            return None
    if re.search(r'\b%s\b' % Iq, E):
        return None
    return E

# Returns (E, rc) if statement S is a GRXRINGS-only dispatcher, else None.
# trailing: the expression of a "return R;" right after S, or None.
def classify(S, I, trailing):
    s = norm(S)
    Iq = re.escape(I)
    R = norm(trailing) if trailing is not None else None
    m = re.match(r'^if \( %s -> cmd == ETHTOOL_GRXRINGS \) \{ %s -> data = ([^;]+) ; return 0 ; \}$' % (Iq, Iq), s)
    if m:
        if R is None or not R.startswith('- '):
            return None
        return (m.group(1), None)
    m = re.match(r'^switch \( %s -> cmd \) \{ case ETHTOOL_GRXRINGS : %s -> data = ([^;]+) ; (.*)\}$' % (Iq, Iq), s)
    if not m:
        return None
    E, rest = m.group(1), m.group(2)
    if re.search(r'\b%s\b' % Iq, E):
        return None
    rc = None
    if rest.startswith('break ; '):
        kind, rest = 'brk', rest[len('break ; '):]
    elif re.match(r'^(\w+) = 0 ; break ; ', rest):
        mm = re.match(r'^(\w+) = 0 ; break ; ', rest)
        kind, rc, rest = 'brk', mm.group(1), rest[mm.end():]
    elif rest.startswith('return 0 ; '):
        kind, rest = 'ret', rest[len('return 0 ; '):]
    else:
        return None
    if rest and not rest.startswith('default : '):
        return None
    if re.search(r'\bcase\b|\bETHTOOL_|\b%s\b' % Iq, rest):
        return None
    if kind == 'brk':
        if R is None or not re.match(r'^\w+$', R):
            return None
        if rc is not None and rc != R:
            return None
        return (E, R)
    # kind == 'ret'
    if R is not None:
        if not R.startswith('- ') or rest:
            return None
        return (E, None)
    if not re.search(r'return - \w+ ; $', rest):
        return None
    return (E, None)

# Header text "static u32 g" for the new callback.  If .get_rxnfc (name on
# line `line`) carries a kernel-doc comment, the new callback gets one too,
# in the same style (same closing line, same @dev description).
def kdoc_header(path, line, g, dev):
    hdr = 'static u32 ' + g
    SL = chr(47)
    OPEN = SL + '**'
    try:
        lines = open(path).read().split('\n')
    except Exception:
        return hdr
    def is_end(t):
        return re.match(r'^\s*\*+[/]\s*$', t) is not None
    i = int(line) - 2
    if i >= 0 and not is_end(lines[i]) and re.match(r'^[A-Za-z_][\w\s\*]*$', lines[i]):
        i -= 1
    if i < 0 or not is_end(lines[i]):
        return hdr
    end = lines[i].rstrip()
    j = i - 1
    while j >= 0 and not lines[j].lstrip().startswith(SL + '*'):
        j -= 1
    if j < 0 or lines[j].strip() != OPEN:
        return hdr
    desc = 'network interface device structure'
    for t in lines[j:i]:
        m = re.match(r'^\s*\*\s*@%s:\s*(.*\S)\s*$' % re.escape(dev), t)
        if m:
            desc = m.group(1)
    doc = [OPEN,
           ' * %s - get RX ring count' % g,
           ' * @%s: %s' % (dev, desc),
           ' *',
           ' * Return: number of RX rings.',
           end]
    return '\n'.join(doc) + '\n' + hdr

# f is only referenced by its definition and .get_rxnfc initializers
def only_callback_refs(path, f):
    try:
        text = open(path).read()
    except Exception:
        return False
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"/[/][^\n]*", " ", text)
    total = len(re.findall(r"\b%s\b" % re.escape(f), text))
    inits = len(re.findall(r"\.get_rxnfc\s*=\s*%s\b" % re.escape(f), text))
    return total == inits + 1

@has@
identifier o;
expression E;
@@
struct ethtool_ops o = { ..., .get_rx_ring_count = E, ... };

@ops@
identifier f, o;
@@
struct ethtool_ops o = { ..., .get_rxnfc = f, ... };

@script:python nm@
f << ops.f;
g;
@@
if "get_rxnfc" in f:
    coccinelle.g = cocci.make_ident(f.replace("get_rxnfc", "get_rx_ring_count"))
else:
    cocci.include_match(False)

// f must not be used other than as the .get_rxnfc callback
@bad@
identifier ops.f;
expression E;
@@
(
 f(...)
|
 E = f
)

// ---------------------------------------------------------------------
// Case A: the whole callback is a GRXRINGS-only dispatcher
// ---------------------------------------------------------------------
@MA depends on !bad && !has@
identifier ops.f, dev, info;
identifier e != ENODEV;
statement S;
position ps;
@@
int f(struct net_device *dev, struct ethtool_rxnfc *info, ...)
{
... when != info
    when != return -e;
S@ps
... when any
}

@MAR@
statement MA.S;
position MA.ps;
expression R;
@@
S@ps
return R;

@MAN@
statement MA.S, S2;
position MA.ps;
@@
S@ps
S2

// NB: filters below never call include_match(False), which would also drop
// the inherited ops/nm bindings for all later rules; instead a rejected
// match yields a sentinel name/expression that cannot match any code.
@script:python pyA@
f << ops.f;
ps << MA.ps;
S << MA.S;
info << MA.info;
R << MAR.R = "";
S2 << MAN.S2 = "";
fa;
E;
RR;
rc;
@@
r = None
if R != "":
    r = classify(S, info, R)
elif S2 == "":
    r = classify(S, info, None)
if r is not None and not only_callback_refs(ps[0].file, f):
    r = None
coccinelle.fa = cocci.make_ident(f if r is not None else "__no_match__")
coccinelle.E = cocci.make_expr(r[0] if r is not None else "__no_match__")
coccinelle.RR = cocci.make_expr(R if R != "" else "__no_trailing_return__")
coccinelle.rc = cocci.make_ident(r[1] if (r is not None and r[1]) else "__no_rc_var__")

@TA@
identifier nm.g, MA.dev, MA.info, pyA.fa;
statement MA.S;
position MA.ps;
expression pyA.E, pyA.RR;
typedef u32;
@@
- int fa(struct net_device *dev, struct ethtool_rxnfc *info, ...)
+ u32 g(struct net_device *dev)
  {
  ... when any
(
- S@ps
- return RR;
+ return E;
|
- S@ps
+ return E;
)
  ... when any
  }

// the now unused status variable
@depends on TA@
identifier nm.g, pyA.rc;
type T;
expression C;
typedef u32;
@@
u32 g(...)
{
  ... when any
- T rc = C;
  ... when != rc
}

// a "no device" guard now reports zero rings instead of an error
@depends on TA@
identifier nm.g;
typedef u32;
@@
u32 g(...)
{
<...
- return -ENODEV;
+ return 0;
...>
}

@AOm depends on TA@
identifier ops.f, o;
position po, pf;
@@
struct ethtool_ops o@po = { ..., .get_rxnfc = f@pf, ... };

@script:python pyAO@
pf << AOm.pf;
g << nm.g;
GI;
@@
coccinelle.GI = cocci.make_ident(aligned_init(pf[0].file, pf[0].line, g))

@depends on TA@
identifier ops.f, o, pyAO.GI;
position AOm.po;
@@
struct ethtool_ops o@po = {
  ...,
- .get_rxnfc = f,
+ GI,
  ...
};

// ---------------------------------------------------------------------
// Case B: extract the GRXRINGS case into a new callback
// ---------------------------------------------------------------------
@MB depends on !bad && !has && !TA exists@
identifier ops.f, dev, info;
statement S;
position pfB;
@@
int f@pfB(struct net_device *dev, struct ethtool_rxnfc *info, ...)
{
... when any
S
... when any
}

@script:python pyB0@
S << MB.S;
info << MB.info;
E;
@@
e = extract_case(S, info)
if e is None:
    cocci.include_match(False)
else:
    coccinelle.E = cocci.make_expr(e)

// the value only depends on one local, initialised from the netdev
@Bd1 exists@
identifier ops.f, MB.dev, MB.info, x, F;
type T;
@@
int f(struct net_device *dev, struct ethtool_rxnfc *info, ...)
{
... when any
T *x = F(dev);
... when any
}

@script:python pyB1@
f << ops.f;
E << pyB0.E;
x << Bd1.x;
fb1;
@@
coccinelle.fb1 = cocci.make_ident(f if only_uses(E, set([x]), set([x])) else "__no_match__")

// ... or on a local derived from such a local (priv -> vsi)
@Bd2 exists@
identifier ops.f, MB.dev, MB.info, x, y, F, fld;
type T1, T2;
@@
int f(struct net_device *dev, struct ethtool_rxnfc *info, ...)
{
... when any
T1 *x = F(dev);
... when any
T2 *y = x->fld;
... when any
}

@script:python pyB2@
f << ops.f;
E << pyB0.E;
x << Bd2.x;
y << Bd2.y;
fb2;
@@
coccinelle.fb2 = cocci.make_ident(f if only_uses(E, set([x, y]), set([y])) else "__no_match__")

@script:python pyB3@
f << ops.f;
E << pyB0.E;
fb1 << pyB1.fb1 = "__no_match__";
fb2 << pyB2.fb2 = "__no_match__";
pfB << MB.pfB;
dev << MB.dev;
g << nm.g;
Eok;
HDR;
@@
coccinelle.HDR = cocci.make_ident(kdoc_header(pfB[0].file, pfB[0].line, g, dev))
coccinelle.Eok = cocci.make_expr(E if f in (fb1, fb2) else "__no_match__")

// remove the GRXRINGS handling from .get_rxnfc
@BTif@
identifier MB.info;
expression pyB3.Eok;
@@
- if (info->cmd == ETHTOOL_GRXRINGS) {
-	info->data = Eok;
-	return 0;
- }

@BT_brk_0_c_1 @
identifier MB.info;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  }

@BT_brk_0_c_2 @
identifier MB.info;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_brk_0_c_3 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_brk_0_c_4 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_brk_0_c_5 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_brk_0_c_6 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_brk_0_c_7 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_brk_0_c_8 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_brk_0_c_9 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_brk_0_c_10 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_brk_0_d_1 @
identifier MB.info;
expression pyB3.Eok;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  default:
  ...
  }

@BT_brk_0_d_2 @
identifier MB.info;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_brk_0_d_3 @
identifier MB.info;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_brk_0_d_4 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_brk_0_d_5 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_brk_0_d_6 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_brk_0_d_7 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_brk_0_d_8 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_brk_0_d_9 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_brk_0_d_10 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_brk_1_c_1 @
identifier MB.info;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  }

@BT_brk_1_c_2 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_brk_1_c_3 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_brk_1_c_4 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_brk_1_c_5 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_brk_1_c_6 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_brk_1_c_7 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_brk_1_c_8 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_brk_1_c_9 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_brk_1_c_10 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_brk_1_d_1 @
identifier MB.info;
expression pyB3.Eok, P1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  default:
  ...
  }

@BT_brk_1_d_2 @
identifier MB.info;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_brk_1_d_3 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_brk_1_d_4 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_brk_1_d_5 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_brk_1_d_6 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_brk_1_d_7 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_brk_1_d_8 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_brk_1_d_9 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_brk_1_d_10 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_brk_2_c_1 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  }

@BT_brk_2_c_2 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_brk_2_c_3 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_brk_2_c_4 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_brk_2_c_5 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_brk_2_c_6 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_brk_2_c_7 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_brk_2_c_8 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_brk_2_c_9 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_brk_2_c_10 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_brk_2_d_1 @
identifier MB.info;
expression pyB3.Eok, P1, P2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  default:
  ...
  }

@BT_brk_2_d_2 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_brk_2_d_3 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_brk_2_d_4 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_brk_2_d_5 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_brk_2_d_6 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_brk_2_d_7 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_brk_2_d_8 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_brk_2_d_9 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_brk_2_d_10 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_rc_0_c_1 @
identifier MB.info, R;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  }

@BT_rc_0_c_2 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_rc_0_c_3 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_rc_0_c_4 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_rc_0_c_5 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_rc_0_c_6 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_rc_0_c_7 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_rc_0_c_8 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_rc_0_c_9 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_rc_0_c_10 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_rc_0_d_1 @
identifier MB.info, R;
expression pyB3.Eok;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  default:
  ...
  }

@BT_rc_0_d_2 @
identifier MB.info, R;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_rc_0_d_3 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_rc_0_d_4 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_rc_0_d_5 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_rc_0_d_6 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_rc_0_d_7 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_rc_0_d_8 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_rc_0_d_9 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_rc_0_d_10 @
identifier MB.info, R;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_rc_1_c_1 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  }

@BT_rc_1_c_2 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_rc_1_c_3 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_rc_1_c_4 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_rc_1_c_5 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_rc_1_c_6 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_rc_1_c_7 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_rc_1_c_8 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_rc_1_c_9 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_rc_1_c_10 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_rc_1_d_1 @
identifier MB.info, R;
expression pyB3.Eok, P1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  default:
  ...
  }

@BT_rc_1_d_2 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_rc_1_d_3 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_rc_1_d_4 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_rc_1_d_5 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_rc_1_d_6 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_rc_1_d_7 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_rc_1_d_8 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_rc_1_d_9 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_rc_1_d_10 @
identifier MB.info, R;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_rc_2_c_1 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  }

@BT_rc_2_c_2 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  }

@BT_rc_2_c_3 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_rc_2_c_4 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_rc_2_c_5 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_rc_2_c_6 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_rc_2_c_7 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_rc_2_c_8 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_rc_2_c_9 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_rc_2_c_10 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_rc_2_d_1 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  default:
  ...
  }

@BT_rc_2_d_2 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  default:
  ...
  }

@BT_rc_2_d_3 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_rc_2_d_4 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_rc_2_d_5 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_rc_2_d_6 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_rc_2_d_7 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_rc_2_d_8 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_rc_2_d_9 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_rc_2_d_10 @
identifier MB.info, R;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- R = 0;
- break;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_ret_0_c_1 @
identifier MB.info;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  }

@BT_ret_0_c_2 @
identifier MB.info;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  }

@BT_ret_0_c_3 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_ret_0_c_4 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_ret_0_c_5 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_ret_0_c_6 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_ret_0_c_7 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_ret_0_c_8 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_ret_0_c_9 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_ret_0_c_10 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_ret_0_d_1 @
identifier MB.info;
expression pyB3.Eok;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  default:
  ...
  }

@BT_ret_0_d_2 @
identifier MB.info;
expression pyB3.Eok, C1;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  default:
  ...
  }

@BT_ret_0_d_3 @
identifier MB.info;
expression pyB3.Eok, C1, C2;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_ret_0_d_4 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_ret_0_d_5 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_ret_0_d_6 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_ret_0_d_7 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_ret_0_d_8 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_ret_0_d_9 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_ret_0_d_10 @
identifier MB.info;
expression pyB3.Eok, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_ret_1_c_1 @
identifier MB.info;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  }

@BT_ret_1_c_2 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  }

@BT_ret_1_c_3 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_ret_1_c_4 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_ret_1_c_5 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_ret_1_c_6 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_ret_1_c_7 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_ret_1_c_8 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_ret_1_c_9 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_ret_1_c_10 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_ret_1_d_1 @
identifier MB.info;
expression pyB3.Eok, P1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  default:
  ...
  }

@BT_ret_1_d_2 @
identifier MB.info;
expression pyB3.Eok, P1, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  default:
  ...
  }

@BT_ret_1_d_3 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_ret_1_d_4 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_ret_1_d_5 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_ret_1_d_6 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_ret_1_d_7 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_ret_1_d_8 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_ret_1_d_9 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_ret_1_d_10 @
identifier MB.info;
expression pyB3.Eok, P1, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }

@BT_ret_2_c_1 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  }

@BT_ret_2_c_2 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  }

@BT_ret_2_c_3 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  }

@BT_ret_2_c_4 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  }

@BT_ret_2_c_5 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  }

@BT_ret_2_c_6 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  }

@BT_ret_2_c_7 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  }

@BT_ret_2_c_8 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  }

@BT_ret_2_c_9 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  }

@BT_ret_2_c_10 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  case C10:
  ...
  }

@BT_ret_2_d_1 @
identifier MB.info;
expression pyB3.Eok, P1, P2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  default:
  ...
  }

@BT_ret_2_d_2 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  default:
  ...
  }

@BT_ret_2_d_3 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  default:
  ...
  }

@BT_ret_2_d_4 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  default:
  ...
  }

@BT_ret_2_d_5 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  default:
  ...
  }

@BT_ret_2_d_6 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  default:
  ...
  }

@BT_ret_2_d_7 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  default:
  ...
  }

@BT_ret_2_d_8 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  default:
  ...
  }

@BT_ret_2_d_9 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  default:
  ...
  }

@BT_ret_2_d_10 @
identifier MB.info;
expression pyB3.Eok, P1, P2, C1, C2, C3, C4, C5, C6, C7, C8, C9;
@@
  switch (info->cmd) {
  case P1:
  ...
  case P2:
  ...
- case ETHTOOL_GRXRINGS:
- info->data = Eok;
- return 0;
  case C1:
  ...
  case C2:
  ...
  case C3:
  ...
  case C4:
  ...
  case C5:
  ...
  case C6:
  ...
  case C7:
  ...
  case C8:
  ...
  case C9:
  ...
  default:
  ...
  }


// only add the new callback if the GRXRINGS case is really gone
@still@
identifier ops.f;
@@
f(...) { <+... ETHTOOL_GRXRINGS ...+> }

@BI1 depends on !still@
identifier MB.dev, Bd1.x, Bd1.F, pyB1.fb1, pyB3.HDR;
type Bd1.T;
expression pyB0.E;
typedef u32;
@@
+HDR(struct net_device *dev)
+{
+	T *x = F(dev);
+
+	return E;
+}
+
 int fb1(...) {...}

@BI2 depends on !still && !BI1@
identifier MB.dev, Bd2.x, Bd2.y, Bd2.F, Bd2.fld, pyB2.fb2, pyB3.HDR;
type Bd2.T1, Bd2.T2;
expression pyB0.E;
typedef u32;
@@
+HDR(struct net_device *dev)
+{
+	T1 *x = F(dev);
+	T2 *y = x->fld;
+
+	return E;
+}
+
 int fb2(...) {...}

// the count is now returned as u32
@depends on BI1 || BI2@
identifier nm.g;
expression A, B;
typedef u32;
@@
u32 g(...)
{
...
- return min_t(int, A, B);
+ return min_t(u32, A, B);
}

// the new callback goes right after the later of .get_rxnfc/.set_rxnfc
@BOm depends on BI1 || BI2@
identifier ops.f, o;
position po, pg;
@@
struct ethtool_ops o@po = { ..., .get_rxnfc = f@pg, ... };

@script:python pyBO@
pg << BOm.pg;
f << ops.f;
g << nm.g;
anchor;
GI;
@@
s = set_after(pg[0].file, pg[0].line)
coccinelle.anchor = cocci.make_ident(s if s else f)
coccinelle.GI = cocci.make_ident(aligned_init(pg[0].file, pg[0].line, g))

@BO@
identifier o, fld, pyBO.anchor, pyBO.GI;
position BOm.po;
@@
struct ethtool_ops o@po = {
  ...,
  .fld = anchor,
+ GI,
  ...
};
