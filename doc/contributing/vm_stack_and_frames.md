# Ruby VM Stack and Frame Layout

This document explains the Ruby VM stack architecture, including how the value
stack (SP) and control frames (CFP) share a single contiguous memory region,
and how individual frames are structured.

## VM Stack Architecture

The Ruby VM uses a single contiguous stack (`ec->vm_stack`) with two different
regions growing toward each other. Understanding this requires distinguishing
the overall architecture (how CFPs and values share one stack) from individual
frame internals (how values are organized for one single frame).

```text
High addresses (ec->vm_stack + ec->vm_stack_size)
    ↓
    [CFP region starts here] ← RUBY_VM_END_CONTROL_FRAME(ec)
    [CFP - 1]                  New frame pushed here (grows downward)
    [CFP - 2]                  Another frame
    ...

    (Unused space - stack overflow when they meet)

    ...                        Value stack grows UP toward higher addresses
    [SP + n]                   Values pushed here
    [ec->cfp->sp]              Current executing frame's stack pointer
    ↑
Low addresses (ec->vm_stack)
```

The "unused space" represents free space available for new frames and values. When this gap closes (CFP meets SP), stack overflow occurs.

### Stack Growth Directions

**Control Frames (CFP):**

- Start at `ec->vm_stack + ec->vm_stack_size` (high addresses)
- Grow **downward** toward lower addresses as frames are pushed
- Each new frame is allocated at `cfp - 1` (lower address)
- The `rb_control_frame_t` structure itself moves downward

**Value Stack (SP):**

- Starts at `ec->vm_stack` (low addresses)
- Grows **upward** toward higher addresses as values are pushed
- Each frame's `cfp->sp` points to the top of its value stack

### Stack Overflow

When recursive calls push too many frames, CFP grows downward until it collides
with SP growing upward. The VM detects this with `CHECK_VM_STACK_OVERFLOW0`,
which computes `const rb_control_frame_struct *bound = (void *)&sp[margin];`
and raises if `cfp <= &bound[1]`.

## Understanding Individual Frame Value Stacks

Each frame has its own portion of the overall VM stack, called its "VM value stack"
or simply "value stack". This space is pre-allocated when the frame is created,
with size determined by:

- `local_size` - space for local variables
- `stack_max` - maximum depth for temporary values during execution

The frame's value stack grows upward from its base (where self/arguments/locals
live) toward `cfp->sp` (the current top of temporary values).

## Visualizing How Frames Fit in the VM Stack

The left side shows the overall VM stack with CFP metadata separated from frame
values. The right side zooms into one frame's value region, revealing its internal
structure.

```text
Overall VM Stack (ec->vm_stack):          Zooming into Frame 2's value stack:

High addr (vm_stack + vm_stack_size)      High addr (cfp->sp)
    ↓                                   ┌
    [CFP 1 metadata]                    │ [Temporaries]
    [CFP 2 metadata] ─────────┐         │ [Env: Flags/Block/CME] ← cfp->ep
    [CFP 3 metadata]          │         │ [Locals]
    ────────────────          │       ┌─┤ [Arguments]
     (unused space)           │       │ │ [self]
    ────────────────          │       │ └
    [Frame 3 values]          │       │   Low addr (frame base)
    [Frame 2 values] <────────┴───────┘
    [Frame 1 values]
    ↑
Low addr (vm_stack)
```

## Examining a Single Frame's Value Stack

Now let's walk through a concrete Ruby program to see how a single frame's
value stack is structured internally:

```ruby
def foo(x, y)
  z = x.casecmp(y)
end

foo(:one, :two)
```

First, after arguments are evaluated and right before the `send` to `foo`:

```text
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

```text
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

Note that this EP-relative index has a different basis than the index that comes
after "@" in disassembly listings. The "@" index is relative to the 0th local
(`x` in this case).

### Q&A

Q: It seems that the receiver is always at an offset relative to EP,
   like locals. Couldn't we use EP to access it instead of using `cfp->self`?

A: Not all calls put the `self` in the callee on the stack. Two
   examples are `Proc#call`, where the receiver is the Proc object, but `self`
   inside the callee is `Proc#receiver`, and `yield`, where the receiver isn't
   pushed onto the stack before the arguments.

Q: Why have `cfp->ep` when it seems that everything is below `cfp->sp`?

A: In the example, `cfp->ep` points to the stack, but it can also point to the
   GC heap. Blocks can capture and evacuate their environment to the heap.
