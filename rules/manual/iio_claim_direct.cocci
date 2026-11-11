// iio_device_claim_direct_mode()/iio_device_release_direct_mode() ->
// sparse-friendly iio_device_claim_direct()/iio_device_release_direct().
// Converts only the idiom
//     ret = iio_device_claim_direct_mode(d); if (ret [< 0]) return ret; | goto L;
// and not when ret was never assigned before the claim and is read after it
// before being re-assigned (the conversion would leave ret uninitialised).
// A function is touched only if every claim in it is convertible; releases
// are renamed only in those functions.  iio_device_claim_direct_scoped() users are left alone.

@initialize:python@
@@
badpos = set()
badfn = set()
def key(p):
    return (p[0].file, p[0].line, p[0].column)

// ---- 1. claims whose ret is still uninitialised apart from the claim and
//         is read again before being re-assigned
@stale exists@
iterator name scoped_guard;
identifier ret;
expression d, E, E1;
assignment operator aop = {+=,-=,*=,/=,|=,&=,^=,<<=,>>=};
position p;
statement S, S1, S2;
type T;
expression E0;
@@
T ret;
... when != ret = E0
    when != &ret
ret = iio_device_claim_direct_mode@p(d);
if (\(ret\|ret < 0\)) S
... when != ret
(
return <+... ret ...+>;
|
if (<+... ret ...+>) S1 else S2
|
if (<+... ret ...+>) S1
|
while (<+... ret ...+>) S1
|
E1 = <+... ret ...+>;
|
E1(..., <+... ret ...+>, ...);
|
ret aop E;
|
\(ret++\|ret--\|++ret\|--ret\);
)

@script:python@
p << stale.p;
@@
badpos.add(key(p))

// ---- 2. convertible claims
@cand@
identifier ret, L;
expression d;
position p;
@@
ret = iio_device_claim_direct_mode@p(d);
if (\(ret\|ret < 0\)) \(return ret;\|goto L;\)

@script:python@
p << cand.p;
@@
if key(p) not in badpos:
    badpos.add(("ok",) + key(p))

// ---- 3. functions containing any claim that will not be converted
@other@
position q;
@@
\(iio_device_claim_direct_mode@q(...)\|iio_device_claim_direct_scoped@q(...)\)

@script:python@
q << other.q;
@@
if ("ok",) + key(q) not in badpos:
    badfn.add((q[0].file, q[0].current_element))

@ok@
position p;
@@
iio_device_claim_direct_mode@p(...)

@script:python keep@
p << ok.p;
f;
@@
if (p[0].file, p[0].current_element) in badfn:
    cocci.include_match(False)
else:
    coccinelle.f = p[0].current_element

// ---- 4. transform
@claim@
identifier keep.f;
identifier ret, L;
expression d;
@@
f(...) {
<...
(
- ret = iio_device_claim_direct_mode(d);
- if (\(ret\|ret < 0\))
-	return ret;
+ if (!iio_device_claim_direct(d))
+	return -EBUSY;
|
- ret = iio_device_claim_direct_mode(d);
- if (\(ret\|ret < 0\))
-	goto L;
+ if (!iio_device_claim_direct(d)) {
+	ret = -EBUSY;
+	goto L;
+ }
)
...>
}

@rel depends on claim@
identifier keep.f;
expression d;
@@
f(...) {
<...
- iio_device_release_direct_mode(d)
+ iio_device_release_direct(d)
...>
}
