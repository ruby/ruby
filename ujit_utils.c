#include <stdio.h>
#include <string.h>
#include "ujit_utils.h"
#include "ujit_asm.h"

// Save caller-save registers on the stack before a C call
void push_regs(codeblock_t* cb)
{
    push(cb, RAX);
    push(cb, RCX);
    push(cb, RDX);
    push(cb, RSI);
    push(cb, RDI);
    push(cb, R8);
    push(cb, R9);
    push(cb, R10);
    push(cb, R11);
    pushfq(cb);
}

// Restore caller-save registers from the after a C call
void pop_regs(codeblock_t* cb)
{
    popfq(cb);
    pop(cb, R11);
    pop(cb, R10);
    pop(cb, R9);
    pop(cb, R8);
    pop(cb, RDI);
    pop(cb, RSI);
    pop(cb, RDX);
    pop(cb, RCX);
    pop(cb, RAX);
}

static void print_str_fn(const char* str)
{
    printf("%s", str);
}

/*
void printInt(CodeBlock as, X86Opnd opnd)
{
    extern (C) void printIntFn(int64_t v)
    {
        writefln("%s", v);
    }

    size_t opndSz;
    if (opnd.isImm)
        opndSz = 64;
    else if (opnd.isGPR)
        opndSz = opnd.reg.size;
    else if (opnd.isMem)
        opndSz = opnd.mem.size;
    else
        assert (false);

    as.pushRegs();

    if (opndSz < 64)
        as.movsx(cargRegs[0].opnd(64), opnd);
    else
        as.mov(cargRegs[0].opnd(64), opnd);

    // Call the print function
    as.ptr(scrRegs[0], &printIntFn);
    as.call(scrRegs[0]);

    as.popRegs();
}
*/

// Print a constant string to stdout
void print_str(codeblock_t* cb, const char* str)
{
    //as.comment("printStr(\"" ~ str ~ "\")");
    size_t len = strlen(str);

    push_regs(cb);

    // Load the string address and jump over the string data
    lea(cb, RDI, mem_opnd(8, RIP, 5));
    jmp32(cb, (int32_t)len + 1);

    // Write the string chars and a null terminator
    for (size_t i = 0; i < len; ++i)
        cb_write_byte(cb, (uint8_t)str[i]);
    cb_write_byte(cb, 0);

    // Call the print function
    mov(cb, RAX, const_ptr_opnd(&print_str_fn));
    call(cb, RAX);

    pop_regs(cb);
}
