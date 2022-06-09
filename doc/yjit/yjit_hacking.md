# YJIT Hacking

## Code Generation and Assembly Language

YJIT’s basic purpose is to take ISEQs and generate machine code.

Documentation on each Ruby bytecode can be found in insns.def.

YJIT uses those bytecodes as the “Basic Blocks” in Lazy Basic Block Versioning (LBBV.) For more deep details of LBBV, see yjit.md in this directory.

Current YJIT has a simple assembler as a backend. Each method that generates code does it by emitting machine code:

```
# Excerpt of yjit_gen_exit() from yjit_codegen.c, Sept 2021
// Generate an exit to return to the interpreter
static uint32_t
yjit_gen_exit(VALUE *exit_pc, ctx_t *ctx, codeblock_t *cb)
{
    const uint32_t code_pos = cb->write_pos;

    ADD_COMMENT(cb, "exit to interpreter");

    // Generate the code to exit to the interpreters
    // Write the adjusted SP back into the CFP
    if (ctx->sp_offset != 0) {
        x86opnd_t stack_pointer = ctx_sp_opnd(ctx, 0);
        lea(cb, REG_SP, stack_pointer);
        mov(cb, member_opnd(REG_CFP, rb_control_frame_t, sp), REG_SP);
    }

    // Update CFP->PC
    mov(cb, RAX, const_ptr_opnd(exit_pc));
    mov(cb, member_opnd(REG_CFP, rb_control_frame_t, pc), RAX);
```

Later there will be a more complex backend.

## Code Generation vs Code Execution

When you see lea() call above (“load effective address,”) it’s not running the LEA x86 instruction. It’s generating an LEA instruction to the codeblock pointer in the first argument. It will execute that instruction later, when the codeblock gets executed.

This is subtle because YJIT will often wait to compile the method until you’re about to run it -- that’s when it knows the most about what types of arguments the method will receive. So it’s a compile-time instruction, but often it will defer compile-time until just barely before runtime.

The ctx structure tracks what is known at compile time about the arguments being passed into the Ruby bytecode. Often YJIT will “peek” at an expected type before it generates machine code.

## Inlined and Outlined Code

When YJIT is generating code, it needs a code pointer. In many cases it needs two, usually called “cb” (codeblock) and “ocb” (out-of-line codeblock.)

cb is for “inlined” normal code and ocb is for “outline” code such as exits. Inlined code is normal generated code for Ruby operations, while outlined code is for unusual and error conditions, such as encountering an unexpected parameter type and exiting to the interpreter.

The purpose of the outlined code block is to keep things we believe are going to be infrequent somewhere else. That way we can keep the code in the inline block more linear and compact. Linear code, with as few branches as possible, is more easily predicted by the CPU. An exception or unsupported operation will cause YJIT to generate outlined code to handle it.

If you search for ocb in yjit_codegen.c, you can see some places where out-of-line code is generated.

YJIT statistics are only gathered when RUBY_DEBUG or YJIT_STATS is true. In some cases the code to increment YJIT statistics will be generated out-of-line, especially if those statistics are gathered when a side exit happens.

## Statistics and Comments

When RUBY_DEBUG is defined to a true value, YJIT will emit comments into the generated machine code. This can make disassemblies a lot more readable. When RUBY_DEBUG or YJIT_STATS is defined and stats are active (--yjit-stats or export YJIT_STATS=1), code will be generated to collect statistics during the run, and a report will be printed when the process exits.

## Entering and Exiting the Interpreter

YJIT won’t generate machine code for an ISEQ until it’s been run a certain number of times (10 by default.) Then, the next time the interpreter would call that ISEQ, it will call the generated machine code version instead. If YJIT hits an unexpected or unsupported operation, it will return to the normal interpreter.

If YJIT returns to the interpreter, the behaviour will be correct but slower. YJIT only optimises part of some operations - for instance, YJIT will not optimise a BMETHOD call yet.

When the interpreter calls to a YJIT-optimised method again, control will return to YJIT’s generated machine code. The more time that’s spent in YJIT-generated code (“ratio in YJIT,”) the more CPU time YJIT can save with its optimisations.

## Side Exits

When YJIT has compiled an ISEQ and is running it later, sometimes it will hit an unexpected condition. It might see a parameter of a different type than before, or square-brackets might be used on a hash when they were first used on an array. In those cases, the generated code will contain a call to return to the interpreter at runtime, called a “side exit.”

Side exits are generated as out-of-line code.

