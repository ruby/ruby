# Stack unwinding with YJIT

Ruby generates C-language backtraces by default when certain fatal signals or other bugs are encountered. These are often useful for identifying the source of a problem inside a C extension, or in the Ruby interpreter itself. In order to generate these, it calls the `backtrace(3)` C standard library function (see vm_dump.c).

YJIT-generated machine code might also be on the stack when a backtrace is generated. Because this code is generated dynamically at run-time, YJIT needs to take some specific steps to make sure that the unwinder in `backtrace(3)` can understand this code and incorporate it in the generated stack trace. This would normally be transparently handled by the compiler for regular code.

## Stack unwinding - a primer.

Distilled down to its essence, stack unwinding is the mechanics of solving the following problem: given the current state of the CPU's registers and the stack, what piece of code is currently running right now? What piece of code called that one? And so on for each previous call, up to the entry point of the program (i.e. `main`).

The answer to "what piece of code is currently running" is normally fairly trivial; every mainstream CPU architecture has an "instruction pointer" register (ip), which points at the currently-executing instruction.

The tricky thing to find out is what the _previous_ value of the ip was, when the call to this function was made. This information must be present somewhere, because the function needs to know where to return control to when it's finished (i.e. - it needs to know the return address). So, how does the `backtrace(3)` function work this out?

There are (at least!) two ways in which this can be done.

### Frame pointer chains

The traditional way this worked is by using frame pointers. The precise scheme is actually CPU/platform dependent, however in general one CPU register is designated as the "frame pointer" (fp). The compiler inserts a prologue at the beginning of every function which saves the previous frame pointer to the stack, and then sets the fp register to point at the bottom of the stack. The compiler also inserts an epilogue which restores the previous value of the fp register on return.

To make things more concrete, this is what the standard prologue/epilogue look like on Linux aarch64. On this architecture, x29 is the frame pointer register, and x30 contains the return address (the "link register").

```assembly
# Pushes the previous frame pointer (x29) and the return address (x30) onto the stack,
# decrementing the stack pointer by 0x10 (two 8-byte registers).
stp x29, x30, [sp, #-0x10]!
# Copies the stack pointer to x29, the frame pointer register.
mov x29, sp

# function body
# Maybe sp is decremented further to make room for local variables.
sub sp, sp, 0xF0
# ...
add sp, sp, 0xF0

# Restore 
ldp x29, x30, [sp], #0x10
# Return to the return address address that's now in x30 again.
ret
```

This means that, during the "function body" part of this function, the stack might look something like the following (n.b. - remember that on most mainstream CPU architectures, including aarch64, the stack grows downwards):

       |--------------------------------|       |-- x29 register (fp): 0xFEF0
0xFFFF |                                |       |    sp register (sp): 0xFE00
  .... | Previous frame return address  |       |
0x0FF8 |                                |       |
       |--------------------------------|       |
0xFFF7 |                                |       |
  .... | Previous previous frame fp     |<-|    |
0xFFF0 |                                |  |    |
       |--------------------------------|  |    |
0xFFEF |                                |  |    |
  .... | Previous frame's local vars    |  |    |
0xFF00 |                                |  |    |
       |--------------------------------|  |    |
0xFEFF |                                |  |    |
  .... | Saved x30 (return address)     |  |    |
0xFEF8 |                                |  |    |
       |--------------------------------|  |    |
0xFEF7 |                                |--|    |
  .... | Saved x29 (frame pointer)      |       |
0xFEF0 |      (value: 0xFEF0)           |<------|
  .... |--------------------------------|
0xFEEF |                                |
  .... | This frame's local vars        |
0xFE00 |                                |
  .... |--------------------------------|            

This simple example elides a bunch of complexity, but I found [Raymond Chen](https://devblogs.microsoft.com/oldnewthing/20220824-00/?p=107043) to be a good resource (it actually works the same on aarch64 Windows as well as Linux).

Anyway, with our frame pointer register, and the saved return address that we _know_ sits below it on the stack, we can answer the original question ("how can I know of the address of the thing that called me?") with a simple pair of rules

* `*(fp + 8)` --> ip in previous frame
* `*fp`       --> fp in previous frame

Or, in words, we know that the fp register (x29) points to the previous value of the fp register, and the previous fp/ip are always stored on the stack in pairs.

Starting from the initial values of the CPU registers & the contents of the stack, repeated application of these rules gets us the ip in successively deeper call frames, yielding a chain of code addresses that caused execution to reach where it has; a stack trace.

### Unwind info

Depending on flags, the OS & CPU architecture, compilers often do not actually generate the prologue/epilogue described in the previous section. The frame pointer is not actually needed for the execution of the code, and compilers might be able to generate faster code if they re-use the frame pointer register as a general purpose register instead. This was historically especially true on architectures with small numbers of registers, like 32-bit x86.

Instead, the compiler can generate an "unwind table". The idea behind the unwind table is that the compiler actually knows at every point in the function what it's done with the stack pointer and where it saved registers. The function _must_ have the return address available somewhere (either on the stack or in a register) so it can actually return there; likewise, the compiler knows how much it's incremented the stack pointer in a function, and thus what the previous value of the stack pointer must have been.

Recall that with frame-pointer based unwinding, we had a pair of rules, that given the state of the fp & ip registers in one frame, could recover the fp & ip registers in the previous frame. The compiler actually has enough information to generate rules to do this unwinding, even without a frame pointer - however, the rules actually _change_ depending on the ip. This set of rules is called "Call Frame Information" (CFI).

For example, here's a (very silly and contrived) aarch64 function that _doesn't_ save a frame pointer _or_ the return address to the stack, along with the unwinding rules the compiler would generate for each code location.

```assembly
# By default, the rules are:
#     x30 --> ip in previous frame (this is where aarch64 call instruction puts the return value)
#      sp --> sp in previous frame (we haven't changed it at all)

# Reserve 16 bytes of stack space for this function:
sub sp, sp, 16
# Now, the rules are:
#    x30 --> ip in previous frame
#  sp+16 --> sp in previous frame (we've added 16 to it!)

# Save the callee-saved register x19 to the stack
str x19, [sp, #-0x8]
# This doesn't change the rules.

# Save x30 in x19
mov x19, x30
# Now, the rules are:
#    x19 --> ip in previous frame (we moved the value here)
#  sp+16 --> sp in previous frame


# Call some other function
bl some_other_function
# This doesn't change the rules; the bl instruction clobbers x30 (the return address),
# but we already updated the rules to look in x19 instead.

# Put the stack pointer back how we found it
add sp, sp, 16
# Now, the rules are
#    x19 --> ip in previous frame
#     sp --> sp in previous frame (it's back how it was)

# Restore the previous value of x30
mov x30, x19
# Now, the rules are back how they started
#    x30 --> ip in previous frame
#     sp --> sp in previous frame

ret
```

The compiler can emit these CFI rules into a table. Then, instead of using the static rules of frame-pointer based unwinding, the unwinding code in `backtrace(3)` can read that table and and apply the dynamic rules instead. It generates a stack trace by starting with the current set of registers & stack, looking up the appropriate rules based on the ip, applying those rules to discover the ip & sp (and potentially other register values!) in the previous frame, and repeating.

## Unwinding implementation details

There is a lot of platform specific machinery that goes into actually _implementing_ this idea of dynamic, per-location unwinding rules, and in how tools can make use of it to actually perform unwinding.

### Unwinding on Linux.

On Linux, the per-location unwinding rules table is encoded in a format defined by the [DWARF Call Frame Information standard](https://dwarfstd.org/) (see section 6.4). The DWARF CFI standard defines the concept of a FDE (Frame Debug Entry) and CIE (Common Information Entry). A single FDE defines unwinding rules for a particular function, and a CIE defines effectively snippets of rules which are common between functions (for example, many functions might share an identical prologue).

The compiler generates FDEs and CIEs for the code it generates, and saves them in a section of the binary called `.eh_frame`. The format of the `.eh_frame` section containing the FDEs/CIEs is itself defined by the [Linux Standard Base (LSB)](https://refspecs.linuxfoundation.org/LSB_5.0.0/LSB-Core-generic/LSB-Core-generic/ehframechpt.html).

(Note - the compiler might _also_ generate a similar section called `.debug_frame`; this can contain similar but more detailed information which is of particular use to debuggers. However, everything we discuss in this document is focused on `.eh_frame`.)

This CFI information then has various uses:

* The main use of it is actually to support C++ exceptions, which need to bubble up through the call stack; however, this is of course not relevant for Ruby or YJIT.
* The `backtrace(3)` function from glibc, which Ruby uses as part of `rb_print_backtrace` in vm_dump.c, (indirectly) uses the CFI information. Actually, the libc function is a thin wrapper around libgcc_s's `_Unwind_Backtrace` function. The libgcc_s library, and [its unwinding support routines](https://refspecs.linuxbase.org/LSB_5.0.0/LSB-Core-generic/LSB-Core-generic/libgcc-sman.html), is defined as being a part of the LSB specification, and so must be present on any LSB-compliant Linux system. Even if an application is not compiled with gcc, routines in libgcc_s are still linked in and used as part of stack unwinding when requested.
* GDB (and other debuggers) will look at `.eh_frame` information if present, to support getting the backtraces of running threads.

Importantly, the `.eh_frame` section _MUST_ be present for any of this to work. Neither libgcc's `_Unwind_Backtrace`, nor GDB, will fall back to frame-pointer based unwinding under any circumstances.

However, there are other tools which _only_ use frame-pointer based unwinding. The `perf(1)` tool, as well as eBPF-based programs, can collect stack traces of running programs from _inside_ the kernel. However, the kernel has no facility itself to perform DWARF CFI-based unwinding, and of course can't call out to libgcc_s. Therefore, userspace stacks are collected from the kernel _only_ by frame-pointer unwinding.

Thus, for stack unwinding to work reliably in all circumstances on Linux, an application (and all libraries it uses) needs to be compiled with both full unwind tables (the `-fasynchronous-unwind-tables` gcc flag) and also frame pointers (the `-fno-omit-frame-pointer` gcc flag).

## Unwinding through JIT'd code

At runtime, YJIT allocates fresh pages, writes machine code into them, marks them executable, and jumps into the generated code. None of this freshly generated code is mentioned in the unwinding information stored in the Ruby binary, of course, so by default, the `backtrace(3)` function would not know how to unwind through it. That means that, when unwinding reached a piece of dynamically-generated YJIT code, it would stop, and would not be able to see any frames underneath that.

For example, if YJIT did not generate any unwinding information, a backtrace due to a fatal signal might look something like this:

```
/ruby/miniruby(rb_print_backtrace+0xc) [0xaaaad0276884] /ruby/vm_dump.c:785
/ruby/miniruby(rb_vm_bugreport) /ruby/vm_dump.c:1093
/ruby/miniruby(rb_bug_for_fatal_signal+0xd0) [0xaaaad0075580] /ruby/error.c:813
/ruby/miniruby(sigsegv+0x5c) [0xaaaad01bedac] /ruby/signal.c:919
linux-vdso.so.1(__kernel_rt_sigreturn+0x0) [0xffff91a3e8bc]
/ruby/miniruby(map<(usize, yjit::backend::ir::Insn), (usize, yjit::backend::ir::Insn), yjit::backend::ir::{impl#17}::next_mapped::{closure_env#0}>+0x8c) [0xaaaad03b8b00] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/core/src/option.rs:929
/ruby/miniruby(next_mapped+0x3c) [0xaaaad0291dc0] src/backend/ir.rs:1225
/ruby/miniruby(arm64_split+0x114) [0xaaaad0287744] src/backend/arm64/mod.rs:359
/ruby/miniruby(compile_with_regs+0x80) [0xaaaad028bf84] src/backend/arm64/mod.rs:1106
/ruby/miniruby(compile+0xc4) [0xaaaad0291ae0] src/backend/ir.rs:1158
/ruby/miniruby(gen_single_block+0xe44) [0xaaaad02b1f88] src/codegen.rs:854
/ruby/miniruby(gen_block_series_body+0x9c) [0xaaaad03b0250] src/core.rs:1698
/ruby/miniruby(gen_block_series+0x50) [0xaaaad03b0100] src/core.rs:1676
/ruby/miniruby(branch_stub_hit_body+0x80c) [0xaaaad03b1f68] src/core.rs:2021
/ruby/miniruby({closure#0}+0x28) [0xaaaad02eb86c] src/core.rs:1924
/ruby/miniruby(do_call<yjit::core::branch_stub_hit::{closure_env#0}, *const u8>+0x98) [0xaaaad035ba3c] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/std/src/panicking.rs:492
[0xaaaad035c9b4]
```

The backtrace does not show anything underneath `[0xaaaad035c9b4]` (which is YJIT generated code), because the unwinder (i.e. libgcc_s's `_Unwind_Backtrace` function on Linux) doesn't know how to unwind through it. What we would rather see, is something like this:

```
/ruby/miniruby(rb_print_backtrace+0xc) [0xaaaad0276884] /ruby/vm_dump.c:785
/ruby/miniruby(rb_vm_bugreport) /ruby/vm_dump.c:1093
/ruby/miniruby(rb_bug_for_fatal_signal+0xd0) [0xaaaad0075580] /ruby/error.c:813
/ruby/miniruby(sigsegv+0x5c) [0xaaaad01bedac] /ruby/signal.c:919
linux-vdso.so.1(__kernel_rt_sigreturn+0x0) [0xffff91a3e8bc]
/ruby/miniruby(map<(usize, yjit::backend::ir::Insn), (usize, yjit::backend::ir::Insn), yjit::backend::ir::{impl#17}::next_mapped::{closure_env#0}>+0x8c) [0xaaaad03b8b00] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/core/src/option.rs:929
/ruby/miniruby(next_mapped+0x3c) [0xaaaad0291dc0] src/backend/ir.rs:1225
/ruby/miniruby(arm64_split+0x114) [0xaaaad0287744] src/backend/arm64/mod.rs:359
/ruby/miniruby(compile_with_regs+0x80) [0xaaaad028bf84] src/backend/arm64/mod.rs:1106
/ruby/miniruby(compile+0xc4) [0xaaaad0291ae0] src/backend/ir.rs:1158
/ruby/miniruby(gen_single_block+0xe44) [0xaaaad02b1f88] src/codegen.rs:854
/ruby/miniruby(gen_block_series_body+0x9c) [0xaaaad03b0250] src/core.rs:1698
/ruby/miniruby(gen_block_series+0x50) [0xaaaad03b0100] src/core.rs:1676
/ruby/miniruby(branch_stub_hit_body+0x80c) [0xaaaad03b1f68] src/core.rs:2021
/ruby/miniruby({closure#0}+0x28) [0xaaaad02eb86c] src/core.rs:1924
/ruby/miniruby(do_call<yjit::core::branch_stub_hit::{closure_env#0}, *const u8>+0x98) [0xaaaad035ba3c] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/std/src/panicking.rs:492
[0xaaaad035c9b4]
/ruby/miniruby(try<*const u8, yjit::core::branch_stub_hit::{closure_env#0}>+0x6c) [0xaaaad035b004] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/std/src/panicking.rs:456
/ruby/miniruby(catch_unwind<yjit::core::branch_stub_hit::{closure_env#0}, *const u8>+0x24) [0xaaaad03a1b28] /rustc/897e37553bba8b42751c67658967889d11ecd120/library/std/src/panic.rs:137
/ruby/miniruby(with_vm_lock<yjit::core::branch_stub_hit::{closure_env#0}, *const u8>+0xac) [0xaaaad02a71a8] src/cruby.rs:630
/ruby/miniruby(branch_stub_hit+0xd4) [0xaaaad03b77ac] src/core.rs:1923
[0xaaaad128205c]
/ruby/miniruby(jit_exec+0x5c) [0xaaaad024c3e4] /ruby/vm.c:415
/ruby/miniruby(vm_sendish) /ruby/vm_insnhelper.c:5222
/ruby/miniruby(vm_exec_core+0xb0) [0xaaaad0266290] /ruby/insns.def:834
/ruby/miniruby(rb_vm_exec+0xd0) [0xaaaad0256af0] /ruby/vm.c:2383
/ruby/miniruby(rb_f_eval+0x208) [0xaaaad0257e4c] /ruby/vm_eval.c:1763
[0xaaaad12844ac]
/ruby/miniruby(jit_exec+0xa8) [0xaaaad0256e50] /ruby/vm.c:415
/ruby/miniruby(rb_vm_exec) /ruby/vm.c:2373
/ruby/miniruby(rb_yield_1+0x230) [0xaaaad025cd90] /ruby/vm.c:1387
/ruby/miniruby(int_dotimes+0x1d0) [0xaaaad0110000] /ruby/numeric.c:5697
/ruby/miniruby(vm_call_cfunc_with_frame_+0x120) [0xaaaad0253390] /ruby/vm_insnhelper.c:3329
/ruby/miniruby(vm_sendish+0x15c) [0xaaaad024c37c] /ruby/vm_insnhelper.c:5203
/ruby/miniruby(vm_exec_core+0xc30) [0xaaaad0266e10] /ruby/insns.def:815
/ruby/miniruby(rb_vm_exec+0xd0) [0xaaaad0256af0] /ruby/vm.c:2383
/ruby/miniruby(rb_ec_exec_node+0xc8) [0xaaaad007baec] /ruby/eval.c:287
/ruby/miniruby(ruby_run_node+0x60) [0xaaaad00812c4] /ruby/eval.c:328
/ruby/miniruby(main+0x6c) [0xaaaacffe5c9c] ./main.c:39
```

When YJIT generates the correct unwind info, the crash backtrace can show the complete sequence of calls all the way into `main`.

## YJIT's unwind info support

Enabling unwinding through JIT-generated code requires doing two things:

* Generating the unwinding info for the code that is generated (this is reasonably platform agnostic)
* Registering that unwinding info so that `backtrace(3)`, `gdb`, etc can find it (this is very platform specific).

### Generating unwind info

YJIT splits up generated functions into multiple blocks, and generates code for those blocks separately, connected by appropriate jump instructions. This means that a single "function" (from the point of view of the platform's ABI Calling convention) actually spans multiple blocks of potentially non-contiguous code; a YJIT function might well return from a different block than the original target of the call. Each block needs to have its own independent unwind info, which knows how to recover the return address & previous stack pointer value.

To achieve this, each block YJIT generates has an associated "stack rule". The stack rule describes the assumptions that the generated code makes about the state of the stack when it's executed. In practice, currently, YJIT's stack manipulations are quite simple, and there are only two stack rules:

* `CalledFromC` - this rule is for the YJIT entry prologue; the stack looks liike it does at the beginning of any function call on this platform.
* `NormalJumpFromJITCode` - this rule is for all other YJIT blocks; the block expects the stack to have already been set up by the entry prologue, and the return address & previous stack pointer value are recoverable by undoing the effects of the entry prologue.

If YJIT ever does more complex stack manipulations that span blocks, the unwinder will need to be taught about these as well.

The machine-specific code generators in YJIT use this knowledge of the initial state of the stack to generate unwinding rules as they generate code. Essentially, they generate unwinding rules every time they manipulate the stack, which mirror their effect. In the current implementation, these rules )(`enum CFIDirective` in unwind.rs) simply mirror the [DWARF CFI annotations](https://sourceware.org/binutils/docs/as/CFI-directives.html#g_t_002ecfi_005fstartproc-_005bsimple_005d) provided by the GNU assembler, however as platform support for YJIT expands these rules could be more generic if required.

Once the code for a block is generated, these rules are passed to the `UnwindInfoManager` implementation in unwind.rs, where the platform-specific parts of the process take place.

### Registering unwind info (Linux)

Frustratingly, on Linux, there are _two_ different interfaces that need to be used to register dynamic unwind information.

* libgcc provides a [`__register_frame`](https://gcc.gnu.org/git/?p=gcc.git;a=blob;f=libgcc/unwind-dw2-fde.c;h=7b74c391ced1b70990736161a22c9adcea524a04;hb=HEAD#l148) function which adds dynamically-generated unwinding info in a place that `_Unwind_Backtrace` (and hence `backtrace(3)`) can find it. This function expects a pointer to a block of memory which contains the contents of a complete, valid `.eh_frame` section - which is to say, it contains a byte buffer containing CIEs and FDEs, terminating in a zero-length FDE.
* gdb defines a [JIT interface](https://sourceware.org/gdb/onlinedocs/gdb/JIT-Interface.html) which JIT compilers can use to add dynamically-generated unwinding info. This requires the application to maintain a linked list of `struct jit_code_entry` objects, each of which have a field `symfile_addr` pointing at the unwind info. However, gdb does not simply expect the contents of an `.eh_frame` section; rather, it expects a complete, valid ELF file laid out in memory, which _contains_ an `.eh_frame` section. This interface is also used by `lldb`.

In order to make unwinding work both with crashdumps and debuggers, YJIT needs to implement _both_ of these interfaces. Maintaining the complete object file expected by GDB is quite tricky, because an ELF file cannot really be appended to, and we'd rather not have to copy around unwind information for the whole process every time we generate a single new small block. However, it's also impractical to generate a complete object file for every code block (this would be both memory inefficient and make the unwinding very slow!). Furthermore, any growth scheme is complicated by the fact that it is unsafe to modify the unwind info while it's registered.

The `UnwindInfoManager` implementation squares this circle by maintaining a _pair_ of object files, with an `.eh_frame` section containing empty space for expansion. At any given time, one is "active" (and registered with libgcc/gdb), and one is "standby".

When a new block of code is generated, and the assembler passes the `enum CFIDirective` rules to the `UnwindInfoManager`, the manager converts those into a real DWARF CFI FDE structure, and then attempts to append it to the "standby" object's `.eh_frame` section. If it doesn't fit, a new standby object is created with a bigger section. Then, the standby info is registered, the active info is de-registered, and the standby object is copied to the active one. This avoids the need for copying large amounts of unwind info around on a regular basis.

As a side note - it's important that `.eh_frame` sections passed to libgcc's `__register_frame` do _NOT_ describe interleaving regions of memory; each section must describe a single contiguous address range (not all of which needs to actually have code) which does not overlap with the range of any other `.eh_frame` section.