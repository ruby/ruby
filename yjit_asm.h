#ifndef YJIT_ASM_H
#define YJIT_ASM_H 1

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
    uint32_t pos;

    // Label which this refers to
    uint32_t label_idx;

} labelref_t;

// Block of executable memory into which instructions can be written
typedef struct CodeBlock
{
    // Memory block
    // Users are advised to not use this directly.
    uint8_t *mem_block_;

    // Memory block size
    uint32_t mem_size;

    // Current writing position
    uint32_t write_pos;

    // Table of registered label addresses
    uint32_t label_addrs[MAX_LABELS];

    // Table of registered label names
    // Note that these should be constant strings only
    const char *label_names[MAX_LABELS];

    // References to labels
    labelref_t label_refs[MAX_LABEL_REFS];

    // Number of labels registeered
    uint32_t num_labels;

    // Number of references to labels
    uint32_t num_refs;


    // Keep track of the current aligned write position.
    // Used for changing protection when writing to the JIT buffer
    uint32_t current_aligned_write_pos;

    // Set if the assembler is unable to output some instructions,
    // for example, when there is not enough space or when a jump
    // target is too far away.
    bool dropped_bytes;

    // Flag to enable or disable comments
    bool has_asm;


} codeblock_t;

// 1 is not aligned so this won't match any pages
#define ALIGNED_WRITE_POSITION_NONE 1

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

// Compute the number of bits needed to store a signed or unsigned value
static inline uint32_t sig_imm_size(int64_t imm);
static inline uint32_t unsig_imm_size(uint64_t imm);

// Memory operand with base register and displacement/offset
static inline x86opnd_t mem_opnd(uint32_t num_bits, x86opnd_t base_reg, int32_t disp);

// Scale-index-base memory operand
static inline x86opnd_t mem_opnd_sib(uint32_t num_bits, x86opnd_t base_reg, x86opnd_t index_reg, int32_t scale, int32_t disp);

// Immediate number operand
static inline x86opnd_t imm_opnd(int64_t val);

// Constant pointer operand
static inline x86opnd_t const_ptr_opnd(const void *ptr);

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

// Allocate executable memory
static uint8_t *alloc_exec_mem(uint32_t mem_size);

// Code block functions
static inline void cb_init(codeblock_t *cb, uint8_t *mem_block, uint32_t mem_size);
static inline void cb_align_pos(codeblock_t *cb, uint32_t multiple);
static inline void cb_set_pos(codeblock_t *cb, uint32_t pos);
static inline void cb_set_write_ptr(codeblock_t *cb, uint8_t *code_ptr);
static inline uint8_t *cb_get_ptr(const codeblock_t *cb, uint32_t index);
static inline uint8_t *cb_get_write_ptr(const codeblock_t *cb);
static inline void cb_write_byte(codeblock_t *cb, uint8_t byte);
static inline void cb_write_bytes(codeblock_t *cb, uint32_t num_bytes, ...);
static inline void cb_write_int(codeblock_t *cb, uint64_t val, uint32_t num_bits);
static inline uint32_t cb_new_label(codeblock_t *cb, const char *name);
static inline void cb_write_label(codeblock_t *cb, uint32_t label_idx);
static inline void cb_label_ref(codeblock_t *cb, uint32_t label_idx);
static inline void cb_link_labels(codeblock_t *cb);
static inline void cb_mark_all_writeable(codeblock_t *cb);
static inline void cb_mark_position_writeable(codeblock_t *cb, uint32_t write_pos);
static inline void cb_mark_all_executable(codeblock_t *cb);

// Encode individual instructions into a code block
static inline void add(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void and(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void call_ptr(codeblock_t *cb, x86opnd_t scratch_reg, uint8_t *dst_ptr);
static inline void call_label(codeblock_t *cb, uint32_t label_idx);
static inline void call(codeblock_t *cb, x86opnd_t opnd);
static inline void cmova(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovae(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovb(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovbe(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovc(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmove(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovg(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovge(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovl(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovle(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovna(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnae(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnb(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnbe(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnc(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovne(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovng(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnge(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnl(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnle(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovno(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnp(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovns(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovnz(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovo(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovp(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovpe(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovpo(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovs(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmovz(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void cmp(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void cdq(codeblock_t *cb);
static inline void cqo(codeblock_t *cb);
static inline void int3(codeblock_t *cb);
static inline void ja_label(codeblock_t *cb, uint32_t label_idx);
static inline void jae_label(codeblock_t *cb, uint32_t label_idx);
static inline void jb_label(codeblock_t *cb, uint32_t label_idx);
static inline void jbe_label(codeblock_t *cb, uint32_t label_idx);
static inline void jc_label(codeblock_t *cb, uint32_t label_idx);
static inline void je_label(codeblock_t *cb, uint32_t label_idx);
static inline void jg_label(codeblock_t *cb, uint32_t label_idx);
static inline void jge_label(codeblock_t *cb, uint32_t label_idx);
static inline void jl_label(codeblock_t *cb, uint32_t label_idx);
static inline void jle_label(codeblock_t *cb, uint32_t label_idx);
static inline void jna_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnae_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnb_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnbe_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnc_label(codeblock_t *cb, uint32_t label_idx);
static inline void jne_label(codeblock_t *cb, uint32_t label_idx);
static inline void jng_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnge_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnl_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnle_label(codeblock_t *cb, uint32_t label_idx);
static inline void jno_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnp_label(codeblock_t *cb, uint32_t label_idx);
static inline void jns_label(codeblock_t *cb, uint32_t label_idx);
static inline void jnz_label(codeblock_t *cb, uint32_t label_idx);
static inline void jo_label(codeblock_t *cb, uint32_t label_idx);
static inline void jp_label(codeblock_t *cb, uint32_t label_idx);
static inline void jpe_label(codeblock_t *cb, uint32_t label_idx);
static inline void jpo_label(codeblock_t *cb, uint32_t label_idx);
static inline void js_label(codeblock_t *cb, uint32_t label_idx);
static inline void jz_label(codeblock_t *cb, uint32_t label_idx);
static inline void ja_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jae_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jb_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jbe_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jc_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void je_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jg_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jge_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jl_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jle_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jna_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnae_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnb_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnbe_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnc_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jne_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jng_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnge_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnl_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnle_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jno_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnp_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jns_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jnz_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jo_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jp_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jpe_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jpo_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void js_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jz_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jmp_label(codeblock_t *cb, uint32_t label_idx);
static inline void jmp_ptr(codeblock_t *cb, uint8_t *ptr);
static inline void jmp_rm(codeblock_t *cb, x86opnd_t opnd);
static inline void jmp32(codeblock_t *cb, int32_t offset);
static inline void lea(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void mov(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void movsx(codeblock_t *cb, x86opnd_t dst, x86opnd_t src);
static inline void neg(codeblock_t *cb, x86opnd_t opnd);
static inline void nop(codeblock_t *cb, uint32_t length);
static inline void not(codeblock_t *cb, x86opnd_t opnd);
static inline void or(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void pop(codeblock_t *cb, x86opnd_t reg);
static inline void popfq(codeblock_t *cb);
static inline void push(codeblock_t *cb, x86opnd_t opnd);
static inline void pushfq(codeblock_t *cb);
static inline void ret(codeblock_t *cb);
static inline void sal(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void sar(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void shl(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void shr(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void sub(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void test(codeblock_t *cb, x86opnd_t rm_opnd, x86opnd_t test_opnd);
static inline void ud2(codeblock_t *cb);
static inline void xchg(codeblock_t *cb, x86opnd_t rm_opnd, x86opnd_t r_opnd);
static inline void xor(codeblock_t *cb, x86opnd_t opnd0, x86opnd_t opnd1);
static inline void cb_write_lock_prefix(codeblock_t *cb);

#endif
