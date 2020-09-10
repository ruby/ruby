#ifndef UJIT_ASM_H
#define UJIT_ASM_H 1

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Maximum number of labels to link
#define MAX_LABELS 32

// Maximum number of label references
#define MAX_LABEL_REFS 32

// Reference to an ASM label
typedef struct LabelRef
{
    // Position in the code block where the label reference exists
    size_t pos;

    // Label which this refers to
    size_t label_idx;

} labelref_t;

// Block of executable memory into which instructions can be written
typedef struct CodeBlock
{
    // Memory block
    uint8_t* mem_block;

    // Memory block size
    size_t mem_size;

    /// Current writing position
    size_t write_pos;

    // Table of registered label addresses
    size_t label_addrs[MAX_LABELS];

    // References to labels
    labelref_t label_refs[MAX_LABEL_REFS];

    // Number of labels registeered
    size_t num_labels;

    // Number of references to labels
    size_t num_refs;

    // TODO: system for disassembly/comment strings, indexed by position

    // Flag to enable or disable comments
    bool has_asm;

} codeblock_t;

enum OpndType
{
    OPND_NONE,
    OPND_REG,
    OPND_IMM,
    OPND_MEM,
    //OPND_IPREL
};

enum RegType
{
    REG_GP,
    REG_FP,
    REG_XMM,
    REG_IP
};

typedef struct X86Reg
{
    // Register type
    uint8_t reg_type;

    // Register index number
    uint8_t reg_no;

} x86reg_t;

typedef struct X86Mem
{
    /// Base register number
    uint8_t base_reg_no;

    /// Index register number
    uint8_t idx_reg_no;

    /// SIB scale exponent value (power of two, two bits)
    uint8_t scale_exp;

    /// Has index register flag
    bool has_idx;

    // TODO: should this be here, or should we have an extra operand type?
    /// IP-relative addressing flag
    bool is_iprel;

    /// Constant displacement from the base, not scaled
    int32_t disp;

} x86mem_t;

typedef struct X86Opnd
{
    // Operand type
    uint8_t type;

    // Size in bits
    uint16_t num_bits;

    union
    {
        // Register operand
        x86reg_t reg;

        // Memory operand
        x86mem_t mem;

        // Signed immediate value
        int64_t imm;

        // Unsigned immediate value
        uint64_t unsigImm;
    };

} x86opnd_t;

// Dummy none/null operand
const x86opnd_t NO_OPND;

// 64-bit GP registers
const x86opnd_t RAX;
const x86opnd_t RCX;
const x86opnd_t RDX;
const x86opnd_t RBX;
const x86opnd_t RBP;
const x86opnd_t RSP;
const x86opnd_t RSI;
const x86opnd_t RDI;
const x86opnd_t R8;
const x86opnd_t R9;
const x86opnd_t R10;
const x86opnd_t R11;
const x86opnd_t R12;
const x86opnd_t R13;
const x86opnd_t R14;
const x86opnd_t R15;

// 32-bit GP registers
const x86opnd_t EAX;
const x86opnd_t ECX;
const x86opnd_t EDX;
const x86opnd_t EBX;
const x86opnd_t EBP;
const x86opnd_t ESP;
const x86opnd_t ESI;
const x86opnd_t EDI;
const x86opnd_t R8D;
const x86opnd_t R9D;
const x86opnd_t R10D;
const x86opnd_t R11D;
const x86opnd_t R12D;
const x86opnd_t R13D;
const x86opnd_t R14D;
const x86opnd_t R15D;

// Memory operand with base register and displacement/offset
x86opnd_t mem_opnd(size_t num_bits, x86opnd_t base_reg, int32_t disp);

// Immediate number operand
x86opnd_t imm_opnd(int64_t val);

void cb_init(codeblock_t* cb, size_t mem_size);
void cb_set_pos(codeblock_t* cb, size_t pos);
uint8_t* cb_get_ptr(codeblock_t* cb, size_t index);
void cb_write_byte(codeblock_t* cb, uint8_t byte);
void cb_write_bytes(codeblock_t* cb, size_t num_bytes, ...);
void cb_write_int(codeblock_t* cb, uint64_t val, size_t num_bits);

// Ruby instruction prologue and epilogue functions
void cb_write_prologue(codeblock_t* cb);
void cb_write_epilogue(codeblock_t* cb);

// Encode individual instructions into a code block
void add(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void call(codeblock_t* cb, x86opnd_t opnd);
void jmp(codeblock_t* cb, x86opnd_t opnd);
void lea(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void mov(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void nop(codeblock_t* cb, size_t length);
void push(codeblock_t* cb, x86opnd_t reg);
void pop(codeblock_t* cb, x86opnd_t reg);
void ret(codeblock_t* cb);
void sal(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void sar(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void shl(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void shr(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void sub(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);

#endif
