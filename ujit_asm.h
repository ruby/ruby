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

    // Table of registered label names
    // Note that these should be constant strings only
    const char* label_names[MAX_LABELS];

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
    OPND_MEM
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
        uint64_t unsig_imm;
    } as;

} x86opnd_t;

// Dummy none/null operand
static const x86opnd_t NO_OPND = { OPND_NONE, 0, .as.imm = 0 };

// Instruction pointer
static const x86opnd_t RIP = { OPND_REG, 64, .as.reg = { REG_IP, 5 }};

// 64-bit GP registers
static const x86opnd_t RAX = { OPND_REG, 64, .as.reg = { REG_GP, 0 }};
static const x86opnd_t RCX = { OPND_REG, 64, .as.reg = { REG_GP, 1 }};
static const x86opnd_t RDX = { OPND_REG, 64, .as.reg = { REG_GP, 2 }};
static const x86opnd_t RBX = { OPND_REG, 64, .as.reg = { REG_GP, 3 }};
static const x86opnd_t RSP = { OPND_REG, 64, .as.reg = { REG_GP, 4 }};
static const x86opnd_t RBP = { OPND_REG, 64, .as.reg = { REG_GP, 5 }};
static const x86opnd_t RSI = { OPND_REG, 64, .as.reg = { REG_GP, 6 }};
static const x86opnd_t RDI = { OPND_REG, 64, .as.reg = { REG_GP, 7 }};
static const x86opnd_t R8  = { OPND_REG, 64, .as.reg = { REG_GP, 8 }};
static const x86opnd_t R9  = { OPND_REG, 64, .as.reg = { REG_GP, 9 }};
static const x86opnd_t R10 = { OPND_REG, 64, .as.reg = { REG_GP, 10 }};
static const x86opnd_t R11 = { OPND_REG, 64, .as.reg = { REG_GP, 11 }};
static const x86opnd_t R12 = { OPND_REG, 64, .as.reg = { REG_GP, 12 }};
static const x86opnd_t R13 = { OPND_REG, 64, .as.reg = { REG_GP, 13 }};
static const x86opnd_t R14 = { OPND_REG, 64, .as.reg = { REG_GP, 14 }};
static const x86opnd_t R15 = { OPND_REG, 64, .as.reg = { REG_GP, 15 }};

// 32-bit GP registers
static const x86opnd_t EAX  = { OPND_REG, 32, .as.reg = { REG_GP, 0 }};
static const x86opnd_t ECX  = { OPND_REG, 32, .as.reg = { REG_GP, 1 }};
static const x86opnd_t EDX  = { OPND_REG, 32, .as.reg = { REG_GP, 2 }};
static const x86opnd_t EBX  = { OPND_REG, 32, .as.reg = { REG_GP, 3 }};
static const x86opnd_t ESP  = { OPND_REG, 32, .as.reg = { REG_GP, 4 }};
static const x86opnd_t EBP  = { OPND_REG, 32, .as.reg = { REG_GP, 5 }};
static const x86opnd_t ESI  = { OPND_REG, 32, .as.reg = { REG_GP, 6 }};
static const x86opnd_t EDI  = { OPND_REG, 32, .as.reg = { REG_GP, 7 }};
static const x86opnd_t R8D  = { OPND_REG, 32, .as.reg = { REG_GP, 8 }};
static const x86opnd_t R9D  = { OPND_REG, 32, .as.reg = { REG_GP, 9 }};
static const x86opnd_t R10D = { OPND_REG, 32, .as.reg = { REG_GP, 10 }};
static const x86opnd_t R11D = { OPND_REG, 32, .as.reg = { REG_GP, 11 }};
static const x86opnd_t R12D = { OPND_REG, 32, .as.reg = { REG_GP, 12 }};
static const x86opnd_t R13D = { OPND_REG, 32, .as.reg = { REG_GP, 13 }};
static const x86opnd_t R14D = { OPND_REG, 32, .as.reg = { REG_GP, 14 }};
static const x86opnd_t R15D = { OPND_REG, 32, .as.reg = { REG_GP, 15 }};

// 16-bit GP registers
static const x86opnd_t AX   = { OPND_REG, 16, .as.reg = { REG_GP, 0 }};
static const x86opnd_t CX   = { OPND_REG, 16, .as.reg = { REG_GP, 1 }};
static const x86opnd_t DX   = { OPND_REG, 16, .as.reg = { REG_GP, 2 }};
static const x86opnd_t BX   = { OPND_REG, 16, .as.reg = { REG_GP, 3 }};
static const x86opnd_t SP   = { OPND_REG, 16, .as.reg = { REG_GP, 4 }};
static const x86opnd_t BP   = { OPND_REG, 16, .as.reg = { REG_GP, 5 }};
static const x86opnd_t SI   = { OPND_REG, 16, .as.reg = { REG_GP, 6 }};
static const x86opnd_t DI   = { OPND_REG, 16, .as.reg = { REG_GP, 7 }};
static const x86opnd_t R8W  = { OPND_REG, 16, .as.reg = { REG_GP, 8 }};
static const x86opnd_t R9W  = { OPND_REG, 16, .as.reg = { REG_GP, 9 }};
static const x86opnd_t R10W = { OPND_REG, 16, .as.reg = { REG_GP, 10 }};
static const x86opnd_t R11W = { OPND_REG, 16, .as.reg = { REG_GP, 11 }};
static const x86opnd_t R12W = { OPND_REG, 16, .as.reg = { REG_GP, 12 }};
static const x86opnd_t R13W = { OPND_REG, 16, .as.reg = { REG_GP, 13 }};
static const x86opnd_t R14W = { OPND_REG, 16, .as.reg = { REG_GP, 14 }};
static const x86opnd_t R15W = { OPND_REG, 16, .as.reg = { REG_GP, 15 }};

// 8-bit GP registers
static const x86opnd_t AL   = { OPND_REG, 8, .as.reg = { REG_GP, 0 }};
static const x86opnd_t CL   = { OPND_REG, 8, .as.reg = { REG_GP, 1 }};
static const x86opnd_t DL   = { OPND_REG, 8, .as.reg = { REG_GP, 2 }};
static const x86opnd_t BL   = { OPND_REG, 8, .as.reg = { REG_GP, 3 }};
static const x86opnd_t SPL  = { OPND_REG, 8, .as.reg = { REG_GP, 4 }};
static const x86opnd_t BPL  = { OPND_REG, 8, .as.reg = { REG_GP, 5 }};
static const x86opnd_t SIL  = { OPND_REG, 8, .as.reg = { REG_GP, 6 }};
static const x86opnd_t DIL  = { OPND_REG, 8, .as.reg = { REG_GP, 7 }};
static const x86opnd_t R8B  = { OPND_REG, 8, .as.reg = { REG_GP, 8 }};
static const x86opnd_t R9B  = { OPND_REG, 8, .as.reg = { REG_GP, 9 }};
static const x86opnd_t R10B = { OPND_REG, 8, .as.reg = { REG_GP, 10 }};
static const x86opnd_t R11B = { OPND_REG, 8, .as.reg = { REG_GP, 11 }};
static const x86opnd_t R12B = { OPND_REG, 8, .as.reg = { REG_GP, 12 }};
static const x86opnd_t R13B = { OPND_REG, 8, .as.reg = { REG_GP, 13 }};
static const x86opnd_t R14B = { OPND_REG, 8, .as.reg = { REG_GP, 14 }};
static const x86opnd_t R15B = { OPND_REG, 8, .as.reg = { REG_GP, 15 }};

// C argument registers
#define NUM_C_ARG_REGS 6
#define C_ARG_REGS ( (x86opnd_t[]){ RDI, RSI, RDX, RCX, R8, R9 } )

// Memory operand with base register and displacement/offset
x86opnd_t mem_opnd(size_t num_bits, x86opnd_t base_reg, int32_t disp);

// Immediate number operand
x86opnd_t imm_opnd(int64_t val);

// Constant pointer operand
x86opnd_t const_ptr_opnd(void* ptr);

// Struct member operand
#define member_opnd(base_reg, struct_type, member_name) mem_opnd( \
    8 * sizeof(((struct_type*)0)->member_name), \
    base_reg,                                   \
    offsetof(struct_type, member_name)          \
)

// Struct member operand with an array index
#define member_opnd_idx(base_reg, struct_type, member_name, idx) mem_opnd( \
    8 * sizeof(((struct_type*)0)->member_name[0]),     \
    base_reg,                                       \
    (offsetof(struct_type, member_name) +           \
     sizeof(((struct_type*)0)->member_name[0]) * idx)  \
)

// Code block methods
uint8_t* alloc_exec_mem(size_t mem_size);
void cb_init(codeblock_t* cb, uint8_t* mem_block, size_t mem_size);
void cb_align_pos(codeblock_t* cb, size_t multiple);
void cb_set_pos(codeblock_t* cb, size_t pos);
uint8_t* cb_get_ptr(codeblock_t* cb, size_t index);
void cb_write_byte(codeblock_t* cb, uint8_t byte);
void cb_write_bytes(codeblock_t* cb, size_t num_bytes, ...);
void cb_write_int(codeblock_t* cb, uint64_t val, size_t num_bits);
size_t cb_new_label(codeblock_t* cb, const char* name);
void cb_write_label(codeblock_t* cb, size_t label_idx);
void cb_label_ref(codeblock_t* cb, size_t label_idx);
void cb_link_labels(codeblock_t* cb);

// Encode individual instructions into a code block
void add(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void and(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void call_label(codeblock_t* cb, size_t label_idx);
void call(codeblock_t* cb, x86opnd_t opnd);
void cmova(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovae(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovb(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovbe(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovc(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmove(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovg(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovge(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovl(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovle(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovna(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnae(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnb(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnbe(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnc(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovne(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovng(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnge(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnl(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnle(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovno(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnp(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovns(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovnz(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovo(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovp(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovpe(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovpo(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovs(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmovz(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void cmp(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void cdq(codeblock_t* cb);
void cqo(codeblock_t* cb);
void int3(codeblock_t* cb);
void ja(codeblock_t* cb, size_t label_idx);
void jae(codeblock_t* cb, size_t label_idx);
void jb(codeblock_t* cb, size_t label_idx);
void jbe(codeblock_t* cb, size_t label_idx);
void jc(codeblock_t* cb, size_t label_idx);
void je(codeblock_t* cb, size_t label_idx);
void jg(codeblock_t* cb, size_t label_idx);
void jge(codeblock_t* cb, size_t label_idx);
void jl(codeblock_t* cb, size_t label_idx);
void jle(codeblock_t* cb, size_t label_idx);
void jna(codeblock_t* cb, size_t label_idx);
void jnae(codeblock_t* cb, size_t label_idx);
void jnb(codeblock_t* cb, size_t label_idx);
void jnbe(codeblock_t* cb, size_t label_idx);
void jnc(codeblock_t* cb, size_t label_idx);
void jne(codeblock_t* cb, size_t label_idx);
void jng(codeblock_t* cb, size_t label_idx);
void jnge(codeblock_t* cb, size_t label_idx);
// void jnl(codeblock_t* cb, size_t label_idx); // this conflicts with jnl(3)
void jnle(codeblock_t* cb, size_t label_idx);
void jno(codeblock_t* cb, size_t label_idx);
void jnp(codeblock_t* cb, size_t label_idx);
void jns(codeblock_t* cb, size_t label_idx);
void jnz(codeblock_t* cb, size_t label_idx);
void jo(codeblock_t* cb, size_t label_idx);
void jp(codeblock_t* cb, size_t label_idx);
void jpe(codeblock_t* cb, size_t label_idx);
void jpo(codeblock_t* cb, size_t label_idx);
void js(codeblock_t* cb, size_t label_idx);
void jz(codeblock_t* cb, size_t label_idx);
void ja_ptr(codeblock_t* cb, uint8_t* ptr);
void jae_ptr(codeblock_t* cb, uint8_t* ptr);
void jb_ptr(codeblock_t* cb, uint8_t* ptr);
void jbe_ptr(codeblock_t* cb, uint8_t* ptr);
void jc_ptr(codeblock_t* cb, uint8_t* ptr);
void je_ptr(codeblock_t* cb, uint8_t* ptr);
void jg_ptr(codeblock_t* cb, uint8_t* ptr);
void jge_ptr(codeblock_t* cb, uint8_t* ptr);
void jl_ptr(codeblock_t* cb, uint8_t* ptr);
void jle_ptr(codeblock_t* cb, uint8_t* ptr);
void jna_ptr(codeblock_t* cb, uint8_t* ptr);
void jnae_ptr(codeblock_t* cb, uint8_t* ptr);
void jnb_ptr(codeblock_t* cb, uint8_t* ptr);
void jnbe_ptr(codeblock_t* cb, uint8_t* ptr);
void jnc_ptr(codeblock_t* cb, uint8_t* ptr);
void jne_ptr(codeblock_t* cb, uint8_t* ptr);
void jng_ptr(codeblock_t* cb, uint8_t* ptr);
void jnge_ptr(codeblock_t* cb, uint8_t* ptr);
void jnl_ptr(codeblock_t* cb, uint8_t* ptr);
void jnle_ptr(codeblock_t* cb, uint8_t* ptr);
void jno_ptr(codeblock_t* cb, uint8_t* ptr);
void jnp_ptr(codeblock_t* cb, uint8_t* ptr);
void jns_ptr(codeblock_t* cb, uint8_t* ptr);
void jnz_ptr(codeblock_t* cb, uint8_t* ptr);
void jo_ptr(codeblock_t* cb, uint8_t* ptr);
void jp_ptr(codeblock_t* cb, uint8_t* ptr);
void jpe_ptr(codeblock_t* cb, uint8_t* ptr);
void jpo_ptr(codeblock_t* cb, uint8_t* ptr);
void js_ptr(codeblock_t* cb, uint8_t* ptr);
void jz_ptr(codeblock_t* cb, uint8_t* ptr);
void jmp(codeblock_t* cb, size_t label_idx);
void jmp_ptr(codeblock_t* cb, uint8_t* ptr);
void jmp_rm(codeblock_t* cb, x86opnd_t opnd);
void jmp32(codeblock_t* cb, int32_t offset);
void lea(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void mov(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void movsx(codeblock_t* cb, x86opnd_t dst, x86opnd_t src);
void neg(codeblock_t* cb, x86opnd_t opnd);
void nop(codeblock_t* cb, size_t length);
void not(codeblock_t* cb, x86opnd_t opnd);
void or(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void pop(codeblock_t* cb, x86opnd_t reg);
void popfq(codeblock_t* cb);
void push(codeblock_t* cb, x86opnd_t reg);
void pushfq(codeblock_t* cb);
void ret(codeblock_t* cb);
void sal(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void sar(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void shl(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void shr(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void sub(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);
void test(codeblock_t* cb, x86opnd_t rm_opnd, x86opnd_t imm_opnd);
void ud2(codeblock_t* cb);
void xor(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1);

#endif
