#spatch --max-width 100
// devm_kmemdup(dev, src, n * sizeof(*src), gfp)
//   -> devm_kmemdup_array(dev, src, n, sizeof(*src), gfp)
// Converted only when the element size is sizeof of an element of the source
// or of the destination (rewritten as sizeof(*src)), or a variable that was
// just set from sizeof. Calls sized with sizeof(some type) are left alone.

// A local length variable used only for the copy is folded into the call
// and its declaration dropped.
@tmp disable paren@
type T;
identifier L;
expression D, S, N, X, G, R;
@@
- T L;
  ... when != L
(
- L = size_mul(sizeof(X), N);
|
- L = size_mul(N, sizeof(X));
|
- L = array_size(sizeof(X), N);
|
- L = array_size(N, sizeof(X));
|
- L = N * sizeof(X);
)
  ... when != L
  R = devm_kmemdup(D, S,
- L
+ N * sizeof(X)
  , G);
  ... when != L

// Assignment: sizeof names an element of the source or of the destination.
// A source given through a cast or address-of is not rewritten here.
@lhs disable paren, drop_cast@
expression R, D, S, N, G, E;
type T0;
@@
R =
(
  devm_kmemdup(D, \( (T0)E \| &E \), ...)
|
- devm_kmemdup(D, S,
-   \( N * sizeof(\( *S \| S[0] \| *R \| R[0] \))
-   \| size_mul(N, sizeof(\( *S \| S[0] \| *R \| R[0] \)))
-   \| size_mul(sizeof(\( *S \| S[0] \| *R \| R[0] \)), N)
-   \| array_size(N, sizeof(\( *S \| S[0] \| *R \| R[0] \)))
-   \| array_size(sizeof(\( *S \| S[0] \| *R \| R[0] \)), N)
-   \), G)
+ devm_kmemdup_array(D, S, N, sizeof(*S), G)
)

// Declaration with initializer: same, for the declared pointer.
@decl disable paren, drop_cast@
type T, T0;
identifier V;
expression D, S, N, G, E;
@@
T *V =
(
  devm_kmemdup(D, \( (T0)E \| &E \), ...)
|
- devm_kmemdup(D, S,
-   \( N * sizeof(\( *S \| S[0] \| *V \| V[0] \))
-   \| size_mul(N, sizeof(\( *S \| S[0] \| *V \| V[0] \)))
-   \| size_mul(sizeof(\( *S \| S[0] \| *V \| V[0] \)), N)
-   \| array_size(N, sizeof(\( *S \| S[0] \| *V \| V[0] \)))
-   \| array_size(sizeof(\( *S \| S[0] \| *V \| V[0] \)), N)
-   \), G)
+ devm_kmemdup_array(D, S, N, sizeof(*S), G)
)
;

// Any context: sizeof names an element of the source.
@src disable paren@
expression D, S, N, G;
@@
- devm_kmemdup(D, S,
-   \( N * sizeof(\( *S \| S[0] \))
-   \| size_mul(N, sizeof(\( *S \| S[0] \)))
-   \| size_mul(sizeof(\( *S \| S[0] \)), N)
-   \| array_size(N, sizeof(\( *S \| S[0] \)))
-   \| array_size(sizeof(\( *S \| S[0] \)), N)
-   \), G)
+ devm_kmemdup_array(D, S, N, sizeof(*S), G)

// Element size held in a variable that was just set from sizeof.
@szvar disable paren@
expression E, X, D, S, N, G;
@@
  E = sizeof(X);
  ... when != E
- devm_kmemdup(D, S, E * N, G)
+ devm_kmemdup_array(D, S, N, E, G)
