// iio_push_to_buffers_with_timestamp(dev, buf, ts) ->
// iio_push_to_buffers_with_ts(dev, buf, sizeof(storage), ts)
// Rewrites only when the size of the scan storage is evident from the argument.

// &storage: local struct, struct member, nested member
@addr@
expression dev, ts, e;
identifier x, f;
@@
(
- iio_push_to_buffers_with_timestamp(dev, &x, ts)
+ iio_push_to_buffers_with_ts(dev, &x, sizeof(x), ts)
|
- iio_push_to_buffers_with_timestamp(dev, &e->f, ts)
+ iio_push_to_buffers_with_ts(dev, &e->f, sizeof(e->f), ts)
|
- iio_push_to_buffers_with_timestamp(dev, &e.f, ts)
+ iio_push_to_buffers_with_ts(dev, &e.f, sizeof(e.f), ts)
)

// array member of the driver state: p->buf
@arr@
expression dev, ts, e;
identifier f;
type T;
T[] a;
@@
- iio_push_to_buffers_with_timestamp(dev, e->f@a, ts)
+ iio_push_to_buffers_with_ts(dev, e->f, sizeof(e->f), ts)

// array member of an embedded scan struct/union (st->scan.data):
// push the whole container so the size covers the timestamp too
@inner@
expression dev, ts, e;
identifier f;
type T;
T[] a;
@@
- iio_push_to_buffers_with_timestamp(dev, e.f@a, ts)
+ iio_push_to_buffers_with_ts(dev, &e, sizeof(e), ts)

// pointer to a scan struct (e.g. kzalloc'ed): sizeof(*p)
@ptr@
expression dev, ts;
identifier S;
idexpression struct S *p;
@@
- iio_push_to_buffers_with_timestamp(dev, p, ts)
+ iio_push_to_buffers_with_ts(dev, p, sizeof(*p), ts)
