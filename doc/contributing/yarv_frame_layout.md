# YARV Frame Layout

This document is an introduction to what happens on the VM stack as the VM
services calls. The code holds the ultimate truth for this subject, so beware
that this document can become stale.

We'll walk through the following program, with explanation at selected points
in execution and abridged disassembly listings:

```ruby
def foo(x, y)
  z = x.casecmp(y)
end

foo(:one, :two)
```

First, after arguments are evaluated and right before the `send` to `foo`:

```
                                ┌────────────┐
  putself                       │    :two    │
  putobject :one            0x2 ├────────────┤
  putobject :two                │    :one    │
► send <:foo, argc:2>       0x1 ├────────────┤
  leave                         │    self    │
                            0x0 └────────────┘
```

The `put*` instructions have pushed 3 items onto the stack. It's now time to
add a new control frame for `foo`. The following is the shape of the stack
after one instruction in `foo`:

```
                                                cfp->sp=0x8 at this point.
                           0x8 ┌────────────┐◄──Stack space for temporaries
                               │    :one    │   live above the environment.
                           0x7 ├────────────┤
  getlocal      x@0            │ < flags  > │   foo's rb_control_frame_t
► getlocal      y@1        0x6 ├────────────┤◄──has cfp->ep=0x6
  send <:casecmp, argc:1>      │ <no block> │
  dup                      0x5 ├────────────┤  The flags, block, and CME triple
  setlocal      z@2            │ <CME: foo> │  (VM_ENV_DATA_SIZE) form an
  leave                    0x4 ├────────────┤  environment. They can be used to
                               │   z (nil)  │  figure out what local variables
                           0x3 ├────────────┤  are below them.
                               │    :two    │
                           0x2 ├────────────┤  Notice how the arguments, now
                               │    :one    │  locals, never moved. This layout
                           0x1 ├────────────┤  allows for argument transfer
                               │    self    │  without copying.
                           0x0 └────────────┘
```

Given that locals have lower address than `cfp->ep`, it makes sense then that
`getlocal` in `insns.def` has `val = *(vm_get_ep(GET_EP(), level) - idx);`.
When accessing variables in the immediate scope, where `level=0`, it's
essentially `val = cfp->ep[-idx];`.

Note that this EP-relative index has a different basis the index that comes
after "@" in disassembly listings. The "@" index is relative to the 0th local
(`x` in this case).

## Q&A

Q: It seems that the receiver is always at an offset relative to EP,
   like locals. Couldn't we use EP to access it instead of using `cfp->self`?

A: Not all calls put the `self` in the callee on the stack. Two
   examples are `Proc#call`, where the receiver is the Proc object, but `self`
   inside the callee is `Proc#receiver`, and `yield`, where the receiver isn't
   pushed onto the stack before the arguments.

Q: Why have `cfp->ep` when it seems that everything is below `cfp->sp`?

A: In the example, `cfp->ep` points to the stack, but it can also point to the
   GC heap. Blocks can capture and evacuate their environment to the heap.
