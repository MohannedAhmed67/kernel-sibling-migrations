// pci_request_regions() -> pcim_request_all_regions() in functions that use
// pcim_enable_device() (managed/"non-hybrid" PCI devres). Manual
// pci_release_regions() calls are then dropped; an error label that only
// released the regions and returned is folded into direct returns.

@en@
identifier f;
expression E;
@@
f(...) { <+... pcim_enable_device(E) ...+> }

@req depends on en@
identifier en.f;
expression en.E, N;
position p;
@@
f(...) { <+... pci_request_regions@p(E, N) ...+> }

@conv depends on req@
identifier en.f;
expression en.E, req.N;
position req.p;
@@
f(...) { <+...
- pci_request_regions@p(E, N)
+ pcim_request_all_regions(E, N)
...+> }

// any unconverted request left in the file -> leave all releases alone
@remaining depends on conv@
expression E, N;
@@
pci_request_regions(E, N)

// error label whose only job was releasing the regions
@lab depends on conv && !remaining exists@
identifier en.f, l, ret;
expression E;
@@
f(...) {
...
l:
pci_release_regions(E);
return ret;
}

// fold the error label into direct returns
@g1 depends on lab@
identifier en.f, lab.l, lab.ret;
expression C, V;
@@
f(...) { <...
- if (C) {
- ret = V;
- goto l;
- }
+ if (C)
+ 	return V;
...> }

@g2 depends on lab@
identifier en.f, lab.l, lab.ret;
expression V;
@@
f(...) { <...
- ret = V;
- goto l;
+ return V;
...> }

@g3 depends on lab@
identifier en.f, lab.l, lab.ret;
expression E;
@@
f(...) { <...
(
- goto l;
+ return ret;
|
- l:
- pci_release_regions(E);
- return ret;
)
...> }

@rel depends on conv && !remaining@
expression E;
@@
- pci_release_regions(E);
