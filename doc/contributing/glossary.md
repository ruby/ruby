# Ruby Internals Glossary

Just a list of acronyms I've run across in the Ruby source code and their meanings.

| Term | Definition |
| ---  | -----------|
| `bmethod` | Method defined by `define_method() {}` (a Block that runs as a Method). |
| `BIN` | Basic Instruction Name. Used as a macro to reference the YARV instruction. Converts pop into YARVINSN_pop. |
| `bop` | Basic Operator. Relates to methods like `Integer` plus and minus which can be optimized as long as they haven't been redefined. |
| `cc` | Call Cache.  An inline cache structure for the call site. Stored in the `cd` |
| `cd` | Call Data. A data structure that points at the `ci` and the `cc`.  `iseq` objects points at the `cd`, and access call information and call caches via this structure |
| CFG | Control Flow Graph. Representation of the program where all control-flow and data dependencies have been made explicit by unrolling the stack and local variables. |
| `cfp`| Control Frame Pointer. Represents a Ruby stack frame.  Calling a method pushes a new frame (cfp), returning pops a frame. Points at  the `pc`, `sp`, `ep`, and the corresponding `iseq`|
| `ci` | Call Information.  Refers to an `rb_callinfo` struct. Contains call information about the call site, including number of parameters to be passed, whether they are keyword arguments or not, etc. Used in conjunction with the `cc` and `cd`. |
| `cme` | Callable Method Entry. Refers to the `rb_callable_method_entry_t` struct, the internal representation of a Ruby method that has `defined_class` and `owner` set and is ready for dispatch. |
| `cref` | Class reference. A structure pointing to the class reference where `klass_or_self`, visibility scope, and refinements are stored. It also stores a pointer to the next class in the hierarchy referenced by `rb_cref_struct * next`. The Class reference is lexically scoped. |
| CRuby | Reference implementation of Ruby written in C |
| `cvar` | Class Variable. Refers to a Ruby class variable like `@@foo` |
| `dvar` | Dynamic Variable. Used by the parser to refer to local variables that are defined outside of the current lexical scope. For example `def foo; bar = 1; -> { p bar }; end` the "bar" inside the block is a `dvar` |
| `ec` | Execution Context. The top level VM context, points at the current `cfp` |
| `ep` | Environment Pointer. Local variables, including method parameters are stored in the `ep` array. The `ep` is pointed to by the `cfp` |
| GC | Garbage Collector |
| `gvar` | Global Variable. Refers to a Ruby global variable like `$$`, etc |
| `ICLASS` | Internal Class. When a module is included, the target class gets a new superclass which is an instance of an `ICLASS`. The `ICLASS` represents the module in the inheritance chain. |
| `ifunc` | Internal FUNCtion. A block implemented in C. |
| `iseq` | Instruction Sequence.  Usually "iseq" in the C code will refer to an `rb_iseq_t` object that holds a reference to the actual instruction sequences which are executed by the VM. The object also holds information about the code, like the method name associated with the code. |
| `insn` | Instruction. Refers to a YARV instruction. |
| `insns` | Instructions. Usually an array of YARV instructions. |
| `ivar` | Instance Variable. Refers to a Ruby instance variable like `@foo` |
| `imemo` | Internal Memo.  A tagged struct whose memory is managed by Ruby's GC, but contains internal information and isn't meant to be exposed to Ruby programs. Contains various information depending on the type.  See the `imemo_type` enum for different types. |
| `IVC` | Instance Variable Cache. Cache specifically for instance variable access |
| JIT | Just In Time compiler |
| `lep` | Local Environment Pointer. An `ep` which is tagged `VM_ENV_FLAG_LOCAL`. Usually this is the `ep` of a method (rather than a block, whose `ep` isn't "local") |
| `local` | Local. Refers to a local variable. |
| `me` | Method Entry. Refers to an `rb_method_entry_t` struct, the internal representation of a Ruby method. |
| MRI | Matz's Ruby Implementation |
| `pc` | Program Counter. Usually the instruction that will be executed _next_ by the VM. Pointed to by the `cfp` and incremented by the VM |
| `snt` | Shared Native Thread. OS thread on which many ruby threads can run. Ruby threads from different ractors can even run on the same SNT. Ruby threads can switch SNTs when they context switch. SNTs are used in the M:N threading model. By default, non-main ractors use this model.
| `dnt` | Dedicated Native Thread. OS thread on which only one ruby thread can run. The ruby thread always runs on that same OS thread. DNTs are used in the 1:1 threading model. By default, the main ractor uses this model.
| `sp` | Stack Pointer. The top of the stack. The VM executes instructions in the `iseq` and instructions will push and pop values on the stack. The VM updates the `sp` on the `cfp` to point at the top of the stack|
| ST table | ST table is the main C implementation of a hash (smaller Ruby hashes may be backed by AR tables). |
| `svar` | Special Variable. Refers to special local variables like `$~` and `$_`. See the `getspecial` instruction in `insns.def` |
| `VALUE` | VALUE is a pointer to a ruby object from the Ruby C code. |
| VM | Virtual Machine. In MRI's case YARV (Yet Another Ruby VM)
| WB | Write Barrier.  To do with GC write barriers |
| WC | Wild Card. As seen in instructions like `getlocal_WC_0`.  It means this instruction takes a "wild card" for the parameter (in this case an index for a local) |
| YARV | Yet Another Ruby VM.  The virtual machine that CRuby uses |
| ZOMBIE | A zombie object. An object that has a finalizer which hasn't been executed yet. The object has been collected, so is "dead", but the finalizer hasn't run yet so it's still somewhat alive. |
