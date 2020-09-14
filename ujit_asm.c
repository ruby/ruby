#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <assert.h>

// For mmapp()
#include <sys/mman.h>

#include "ujit_asm.h"

// Dummy none/null operand
const x86opnd_t NO_OPND = { OPND_NONE, 0, .imm = 0 };

// 64-bit GP registers
const x86opnd_t RAX = { OPND_REG, 64, .reg = { REG_GP, 0 }};
const x86opnd_t RCX = { OPND_REG, 64, .reg = { REG_GP, 1 }};
const x86opnd_t RDX = { OPND_REG, 64, .reg = { REG_GP, 2 }};
const x86opnd_t RBX = { OPND_REG, 64, .reg = { REG_GP, 3 }};
const x86opnd_t RSP = { OPND_REG, 64, .reg = { REG_GP, 4 }};
const x86opnd_t RBP = { OPND_REG, 64, .reg = { REG_GP, 5 }};
const x86opnd_t RSI = { OPND_REG, 64, .reg = { REG_GP, 6 }};
const x86opnd_t RDI = { OPND_REG, 64, .reg = { REG_GP, 7 }};
const x86opnd_t R8  = { OPND_REG, 64, .reg = { REG_GP, 8 }};
const x86opnd_t R9  = { OPND_REG, 64, .reg = { REG_GP, 9 }};
const x86opnd_t R10 = { OPND_REG, 64, .reg = { REG_GP, 10 }};
const x86opnd_t R11 = { OPND_REG, 64, .reg = { REG_GP, 11 }};
const x86opnd_t R12 = { OPND_REG, 64, .reg = { REG_GP, 12 }};
const x86opnd_t R13 = { OPND_REG, 64, .reg = { REG_GP, 13 }};
const x86opnd_t R14 = { OPND_REG, 64, .reg = { REG_GP, 14 }};
const x86opnd_t R15 = { OPND_REG, 64, .reg = { REG_GP, 15 }};

// 32-bit GP registers
const x86opnd_t EAX  = { OPND_REG, 32, .reg = { REG_GP, 0 }};
const x86opnd_t ECX  = { OPND_REG, 32, .reg = { REG_GP, 1 }};
const x86opnd_t EDX  = { OPND_REG, 32, .reg = { REG_GP, 2 }};
const x86opnd_t EBX  = { OPND_REG, 32, .reg = { REG_GP, 3 }};
const x86opnd_t ESP  = { OPND_REG, 32, .reg = { REG_GP, 4 }};
const x86opnd_t EBP  = { OPND_REG, 32, .reg = { REG_GP, 5 }};
const x86opnd_t ESI  = { OPND_REG, 32, .reg = { REG_GP, 6 }};
const x86opnd_t EDI  = { OPND_REG, 32, .reg = { REG_GP, 7 }};
const x86opnd_t R8D  = { OPND_REG, 32, .reg = { REG_GP, 8 }};
const x86opnd_t R9D  = { OPND_REG, 32, .reg = { REG_GP, 9 }};
const x86opnd_t R10D = { OPND_REG, 32, .reg = { REG_GP, 10 }};
const x86opnd_t R11D = { OPND_REG, 32, .reg = { REG_GP, 11 }};
const x86opnd_t R12D = { OPND_REG, 32, .reg = { REG_GP, 12 }};
const x86opnd_t R13D = { OPND_REG, 32, .reg = { REG_GP, 13 }};
const x86opnd_t R14D = { OPND_REG, 32, .reg = { REG_GP, 14 }};
const x86opnd_t R15D = { OPND_REG, 32, .reg = { REG_GP, 15 }};

// Compute the number of bits needed to encode a signed value
size_t sig_imm_size(int64_t imm)
{
    // Compute the smallest size this immediate fits in
    if (imm >= -128 && imm <= 127)
        return 8;
    if (imm >= -32768 && imm <= 32767)
        return 16;
    if (imm >= -2147483648 && imm <= 2147483647)
        return 32;

    return 64;
}

// Compute the number of bits needed to encode an unsigned value
size_t unsig_imm_size(uint64_t imm)
{
    // Compute the smallest size this immediate fits in
    if (imm <= 255)
        return 8;
    else if (imm <= 65535)
        return 16;
    else if (imm <= 4294967295)
        return 32;

    return 64;
}

x86opnd_t mem_opnd(size_t num_bits, x86opnd_t base_reg, int32_t disp)
{
    x86opnd_t opnd = {
        OPND_MEM,
        num_bits,
        .mem = { base_reg.reg.reg_no, 0, 0, false, false, disp }
    };

    return opnd;
}

x86opnd_t imm_opnd(int64_t imm)
{
    x86opnd_t opnd = {
        OPND_IMM,
        sig_imm_size(imm),
        .imm = imm
    };

    return opnd;
}

x86opnd_t const_ptr_opnd(void* ptr)
{
    x86opnd_t opnd = {
        OPND_IMM,
        64,
        .unsig_imm = (uint64_t)ptr
    };

    return opnd;
}

void cb_init(codeblock_t* cb, size_t mem_size)
{
    // Map the memory as executable
    cb->mem_block = (uint8_t*)mmap(
        NULL,
        mem_size,
        PROT_READ | PROT_WRITE | PROT_EXEC,
        MAP_PRIVATE | MAP_ANON,
        -1,
        0
    );

    // Check that the memory mapping was successful
    if (cb->mem_block == MAP_FAILED)
    {
        fprintf(stderr, "mmap call failed\n");
        exit(-1);
    }

    cb->mem_size = mem_size;
    cb->write_pos = 0;
    cb->num_labels = 0;
    cb->num_refs = 0;
}

/**
Set the current write position
*/
void cb_set_pos(codeblock_t* cb, size_t pos)
{
    assert (pos < cb->mem_size);
    cb->write_pos = pos;
}

// Get a direct pointer into the executable memory block
uint8_t* cb_get_ptr(codeblock_t* cb, size_t index)
{
    assert (index < cb->mem_size);
    return &cb->mem_block[index];
}

// Write a byte at the current position
void cb_write_byte(codeblock_t* cb, uint8_t byte)
{
    assert (cb->mem_block);
    assert (cb->write_pos + 1 <= cb->mem_size);
    cb->mem_block[cb->write_pos++] = byte;
}

// Write multiple bytes starting from the current position
void cb_write_bytes(codeblock_t* cb, size_t num_bytes, ...)
{
    va_list va;
    va_start(va, num_bytes);

    for (size_t i = 0; i < num_bytes; ++i)
    {
        uint8_t byte = va_arg(va, int);
        cb_write_byte(cb, byte);
    }

    va_end(va);
}

// Write a signed integer over a given number of bits at the current position
void cb_write_int(codeblock_t* cb, uint64_t val, size_t num_bits)
{
    assert (num_bits > 0);
    assert (num_bits % 8 == 0);

    // Switch on the number of bits
    switch (num_bits)
    {
        case 8:
        cb_write_byte(cb, (uint8_t)val);
        break;

        case 16:
        cb_write_bytes(
            cb,
            2,
            (uint8_t)((val >> 0) & 0xFF),
            (uint8_t)((val >> 8) & 0xFF)
        );
        break;

        case 32:
        cb_write_bytes(
            cb,
            4,
            (uint8_t)((val >>  0) & 0xFF),
            (uint8_t)((val >>  8) & 0xFF),
            (uint8_t)((val >> 16) & 0xFF),
            (uint8_t)((val >> 24) & 0xFF)
        );
        break;

        default:
        {
            // Compute the size in bytes
            size_t num_bytes = num_bits / 8;

            // Write out the bytes
            for (size_t i = 0; i < num_bytes; ++i)
            {
                uint8_t byte_val = (uint8_t)(val & 0xFF);
                cb_write_byte(cb, byte_val);
                val >>= 8;
            }
        }
    }
}

// Allocate a new label with a given name
size_t cb_new_label(codeblock_t* cb, const char* name)
{
    //if (hasASM)
    //    writeString(to!string(label) ~ ":");

    assert (cb->num_labels < MAX_LABELS);

    // Allocate the new label
    size_t label_idx = cb->num_labels++;

    // This label doesn't have an address yet
    cb->label_addrs[label_idx] = 0;
    cb->label_names[label_idx] = name;

    return label_idx;
}

// Write a label at the current address
void cb_write_label(codeblock_t* cb, size_t label_idx)
{
    assert (label_idx < MAX_LABELS);
    cb->label_addrs[label_idx] = cb->write_pos;
}

// Add a label reference at the current write position
void cb_label_ref(codeblock_t* cb, size_t label_idx)
{
    assert (label_idx < MAX_LABELS);
    assert (cb->num_refs < MAX_LABEL_REFS);

    // Keep track of the reference
    cb->label_refs[cb->num_refs] = (labelref_t){ cb->write_pos, label_idx };
    cb->num_refs++;
}

// Link internal label references
void cb_link_labels(codeblock_t* cb)
{
    size_t orig_pos = cb->write_pos;

    // For each label reference
    for (size_t i = 0; i < cb->num_refs; ++i)
    {
        size_t ref_pos = cb->label_refs[i].pos;
        size_t label_idx = cb->label_refs[i].label_idx;
        assert (ref_pos < cb->mem_size);
        assert (label_idx < MAX_LABELS);

        size_t label_addr = cb->label_addrs[label_idx];
        assert (label_addr < cb->mem_size);

        // Compute the offset from the reference's end to the label
        int64_t offset = (int64_t)label_addr - (int64_t)(ref_pos + 4);

        cb_set_pos(cb, ref_pos);
        cb_write_int(cb, offset, 32);
    }

    cb->write_pos = orig_pos;

    // Clear the label positions and references
    cb->num_labels = 0;
    cb->num_refs = 0;
}

// Check if an operand needs a REX byte to be encoded
bool rex_needed(x86opnd_t opnd)
{
    if (opnd.type == OPND_NONE || opnd.type == OPND_IMM)
    {
        return false;
    }

    if (opnd.type == OPND_REG)
    {
        return (
            opnd.reg.reg_no > 7 ||
            (opnd.num_bits == 8 && opnd.reg.reg_no >= 4 && opnd.reg.reg_no <= 7)
        );
    }

    if (opnd.type == OPND_MEM)
    {
        return (opnd.mem.base_reg_no > 7) || (opnd.mem.has_idx && opnd.mem.idx_reg_no > 7);
    }

    assert (false);
}

// Check if an SIB byte is needed to encode this operand
bool sib_needed(x86opnd_t opnd)
{
    if (opnd.type != OPND_MEM)
        return false;

    return (
        opnd.mem.has_idx ||
        opnd.mem.base_reg_no == RSP.reg.reg_no ||
        opnd.mem.base_reg_no == R12.reg.reg_no
    );
}

// Compute the size of the displacement field needed for a memory operand
size_t disp_size(x86opnd_t opnd)
{
    assert (opnd.type == OPND_MEM);

    // If using RIP as the base, use disp32
    if (opnd.mem.is_iprel)
    {
        return 32;
    }

    // Compute the required displacement size
    if (opnd.mem.disp != 0)
    {
        size_t num_bits = sig_imm_size(opnd.mem.disp);
        assert (num_bits <= 32 && "displacement does not fit in 32 bits");

        // x86 can only encode 8-bit and 32-bit displacements
        if (num_bits == 16)
            num_bits = 32;;

        return num_bits;
    }

    // If EBP or RBP or R13 is used as the base, displacement must be encoded
    if (opnd.mem.base_reg_no == RBP.reg.reg_no ||
        opnd.mem.base_reg_no == R13.reg.reg_no)
    {
        return 8;
    }

    return 0;
}

// Write the REX byte
static void cb_write_rex(
    codeblock_t* cb,
    bool w_flag,
    uint8_t reg_no,
    uint8_t idx_reg_no,
    uint8_t rm_reg_no
)
{
    // 0 1 0 0 w r x b
    // w - 64-bit operand size flag
    // r - MODRM.reg extension
    // x - SIB.index extension
    // b - MODRM.rm or SIB.base extension
    uint8_t w = w_flag? 1:0;
    uint8_t r = (reg_no & 8)? 1:0;
    uint8_t x = (idx_reg_no & 8)? 1:0;
    uint8_t b = (rm_reg_no & 8)? 1:0;

    // Encode and write the REX byte
    uint8_t rexByte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
    cb_write_byte(cb, rexByte);
}

// Write an opcode byte with an embedded register operand
static void cb_write_opcode(codeblock_t* cb, uint8_t opcode, x86opnd_t reg)
{
    // Write the reg field into the opcode byte
    uint8_t op_byte = opcode | (reg.reg.reg_no & 7);
    cb_write_byte(cb, op_byte);
}

// Encode an RM instruction
void cb_write_rm(
    codeblock_t* cb,
    bool szPref,
    bool rexW,
    x86opnd_t r_opnd,
    x86opnd_t rm_opnd,
    uint8_t opExt,
    size_t op_len,
    ...)
{
    assert (op_len > 0 && op_len <= 3);
    assert (r_opnd.type == OPND_REG || r_opnd.type == OPND_NONE);

    // Flag to indicate the REX prefix is needed
    bool need_rex = rexW || rex_needed(r_opnd) || rex_needed(rm_opnd);

    // Flag to indicate SIB byte is needed
    bool need_sib = sib_needed(r_opnd) || sib_needed(rm_opnd);

    // Add the operand-size prefix, if needed
    if (szPref == true)
        cb_write_byte(cb, 0x66);

    // Add the REX prefix, if needed
    if (need_rex)
    {
        // 0 1 0 0 w r x b
        // w - 64-bit operand size flag
        // r - MODRM.reg extension
        // x - SIB.index extension
        // b - MODRM.rm or SIB.base extension

        uint8_t w = rexW? 1:0;

        uint8_t r;
        if (r_opnd.type != OPND_NONE)
            r = (r_opnd.reg.reg_no & 8)? 1:0;
        else
            r = 0;

        uint8_t x;
        if (need_sib && rm_opnd.mem.has_idx)
            x = (rm_opnd.mem.idx_reg_no & 8)? 1:0;
        else
            x = 0;

        uint8_t b;
        if (rm_opnd.type == OPND_REG)
            b = (rm_opnd.reg.reg_no & 8)? 1:0;
        else if (rm_opnd.type == OPND_MEM)
            b = (rm_opnd.mem.base_reg_no & 8)? 1:0;
        else
            b = 0;

        // Encode and write the REX byte
        uint8_t rex_byte = 0x40 + (w << 3) + (r << 2) + (x << 1) + (b);
        cb_write_byte(cb, rex_byte);
    }

    // Write the opcode bytes to the code block
    va_list va;
    va_start(va, op_len);
    for (size_t i = 0; i < op_len; ++i)
    {
        uint8_t byte = va_arg(va, int);
        cb_write_byte(cb, byte);
    }
    va_end(va);

    // MODRM.mod (2 bits)
    // MODRM.reg (3 bits)
    // MODRM.rm  (3 bits)

    assert (
        !(opExt != 0xFF && r_opnd.type != OPND_NONE) &&
        "opcode extension and register operand present"
    );

    // Encode the mod field
    uint8_t mod;
    if (rm_opnd.type == OPND_REG)
    {
        mod = 3;
    }
    else
    {
        size_t dsize = disp_size(rm_opnd);
        if (dsize == 0 || rm_opnd.mem.is_iprel)
            mod = 0;
        else if (dsize == 8)
            mod = 1;
        else if (dsize == 32)
            mod = 2;
        else
            assert (false);
    }

    // Encode the reg field
    uint8_t reg;
    if (opExt != 0xFF)
        reg = opExt;
    else if (r_opnd.type == OPND_REG)
        reg = r_opnd.reg.reg_no & 7;
    else
        reg = 0;

    // Encode the rm field
    uint8_t rm;
    if (rm_opnd.type == OPND_REG)
    {
        rm = rm_opnd.reg.reg_no & 7;
    }
    else
    {
        if (need_sib)
            rm = 4;
        else
            rm = rm_opnd.mem.base_reg_no & 7;
    }

    // Encode and write the ModR/M byte
    uint8_t rm_byte = (mod << 6) + (reg << 3) + (rm);
    cb_write_byte(cb, rm_byte);

    // Add the SIB byte, if needed
    if (need_sib)
    {
        // SIB.scale (2 bits)
        // SIB.index (3 bits)
        // SIB.base  (3 bits)

        assert (rm_opnd.type == OPND_MEM);

        // Encode the scale value
        uint8_t scale = rm_opnd.mem.scale_exp;

        // Encode the index value
        uint8_t index;
        if (!rm_opnd.mem.has_idx)
            index = 4;
        else
            index = rm_opnd.mem.idx_reg_no & 7;

        // Encode the base register
        uint8_t base = rm_opnd.mem.base_reg_no & 7;

        // Encode and write the SIB byte
        uint8_t sib_byte = (scale << 6) + (index << 3) + (base);
        cb_write_byte(cb, sib_byte);
    }

    // Add the displacement size
    if (rm_opnd.type == OPND_MEM)
    {
        size_t dsize = disp_size(rm_opnd);
        if (dsize > 0)
            cb_write_int(cb, rm_opnd.mem.disp, dsize);
    }
}

// Encode a mul-like single-operand RM instruction
void write_rm_unary(
    codeblock_t* cb,
    const char* mnem,
    uint8_t opMemReg8,
    uint8_t opMemRegPref,
    uint8_t opExt,
    x86opnd_t opnd)
{
    // Write a disassembly string
    //cb.writeASM(mnem, opnd);

    // Check the size of opnd0
    size_t opndSize;
    if (opnd.type == OPND_REG || opnd.type == OPND_MEM)
        opndSize = opnd.num_bits;
    else
        assert (false && "invalid operand");

    assert (opndSize == 8 || opndSize == 16 || opndSize == 32 || opndSize == 64);
    bool szPref = opndSize == 16;
    bool rexW = opndSize == 64;

    if (opndSize == 8)
        cb_write_rm(cb, false, false, NO_OPND, opnd, opExt, 1, opMemReg8);
    else
        cb_write_rm(cb, szPref, rexW, NO_OPND, opnd, opExt, 1, opMemRegPref);
}

// Encode an add-like RM instruction with multiple possible encodings
void cb_write_rm_multi(
    codeblock_t* cb,
    const char* mnem,
    uint8_t opMemReg8,
    uint8_t opMemRegPref,
    uint8_t opRegMem8,
    uint8_t opRegMemPref,
    uint8_t opMemImm8,
    uint8_t opMemImmSml,
    uint8_t opMemImmLrg,
    uint8_t opExtImm,
    x86opnd_t opnd0,
    x86opnd_t opnd1)
{
    assert (opnd0.type == OPND_REG || opnd0.type == OPND_MEM);

    /*
    // Write disassembly string
    if (!opnd1.isNone)
        cb.writeASM(mnem, opnd0, opnd1);
    else
        cb.writeASM(mnem, opnd0);
    */

    // Check the size of opnd0
    size_t opndSize = opnd0.num_bits;

    // Check the size of opnd1
    if (opnd1.type == OPND_REG || opnd1.type == OPND_MEM)
    {
        assert (opnd1.num_bits == opndSize && "operand size mismatch");
    }
    else if (opnd1.type == OPND_IMM)
    {
        assert (opnd1.num_bits <= opndSize);
    }

    assert (opndSize == 8 || opndSize == 16 || opndSize == 32 || opndSize == 64);
    bool szPref = opndSize == 16;
    bool rexW = opndSize == 64;

    // R/M + Reg
    if ((opnd0.type == OPND_MEM && opnd1.type == OPND_REG) ||
        (opnd0.type == OPND_REG && opnd1.type == OPND_REG))
    {
        // R/M is opnd0
        if (opndSize == 8)
            cb_write_rm(cb, false, false, opnd1, opnd0, 0xFF, 1, opMemReg8);
        else
            cb_write_rm(cb, szPref, rexW, opnd1, opnd0, 0xFF, 1, opMemRegPref);
    }

    // Reg + R/M
    else if (opnd0.type == OPND_REG && opnd1.type == OPND_MEM)
    {
        // R/M is opnd1
        if (opndSize == 8)
            cb_write_rm(cb, false, false, opnd0, opnd1, 0xFF, 1, opRegMem8);
        else
            cb_write_rm(cb, szPref, rexW, opnd0, opnd1, 0xFF, 1, opRegMemPref);
    }

    // R/M + Imm
    else if (opnd1.type == OPND_IMM)
    {
        // 8-bit immediate
        if (opnd1.num_bits <= 8)
        {
            if (opndSize == 8)
                cb_write_rm(cb, false, false, NO_OPND, opnd0, opExtImm, 1, opMemImm8);
            else
                cb_write_rm(cb, szPref, rexW, NO_OPND, opnd0, opExtImm, 1, opMemImmSml);

            cb_write_int(cb, opnd1.imm, 8);
        }

        // 32-bit immediate
        else if (opnd1.num_bits <= 32)
        {
            assert (opnd1.num_bits <= opndSize && "immediate too large for dst");
            cb_write_rm(cb, szPref, rexW, NO_OPND, opnd0, opExtImm, 1, opMemImmLrg);
            cb_write_int(cb, opnd1.imm, (opndSize > 32)? 32:opndSize);
        }

        // Immediate too large
        else
        {
            assert (false && "immediate value too large");
        }
    }

    // Invalid operands
    else
    {
        assert (false && "invalid operand combination");
    }
}

// Encode a single-operand shift instruction
void cb_write_shift(
    codeblock_t* cb,
    const char* mnem,
    uint8_t opMemOnePref,
    uint8_t opMemClPref,
    uint8_t opMemImmPref,
    uint8_t opExt,
    x86opnd_t opnd0,
    x86opnd_t opnd1)
{
    // Write a disassembly string
    //cb.writeASM(mnem, opnd0, opnd1);

    // Check the size of opnd0
    size_t opndSize;
    if (opnd0.type == OPND_REG || opnd0.type == OPND_MEM)
        opndSize = opnd0.num_bits;
    else
        assert (false && "shift: invalid first operand");

    assert (opndSize == 16 || opndSize == 32 || opndSize == 64);
    bool szPref = opndSize == 16;
    bool rexW = opndSize == 64;

    if (opnd1.type == OPND_IMM)
    {
        if (opnd1.imm == 1)
        {
            cb_write_rm(cb, szPref, rexW, NO_OPND, opnd0, opExt, 1, opMemOnePref);
        }
        else
        {
            assert (opnd1.num_bits <= 8);
            cb_write_rm(cb, szPref, rexW, NO_OPND, opnd0, opExt, 1, opMemImmPref);
            cb_write_byte(cb, (uint8_t)opnd1.imm);
        }
    }
    /*
    else if (opnd1.isReg && opnd1.reg == CL)
    {
        cb.writeRMInstr!('l', opExt, opMemClPref)(szPref, rexW, opnd0, X86Opnd.NONE);
    }
    */
    else
    {
        assert (false);
    }
}

// Encode a relative jump to a label (direct or conditional)
// Note: this always encodes a 32-bit offset
void cb_write_jcc(codeblock_t* cb, const char* mnem, uint8_t op0, uint8_t op1, size_t label_idx)
{
    //cb.writeASM(mnem, label);

    // Write the opcode
    cb_write_byte(cb, op0);
    cb_write_byte(cb, op1);

    // Add a reference to the label
    cb_label_ref(cb, label_idx);

    // Relative 32-bit offset to be patched
    cb_write_int(cb, 0, 32);
}

// Encode a conditional move instruction
/*
void writeCmov(CodeBlock cb, const char mnem, ubyte opcode1, X86Reg dst, X86Opnd src)
{
    //cb.writeASM(mnem, dst, src);

    assert (src.isReg || src.isMem);
    assert (dst.size >= 16, "invalid dst reg size in cmov");

    auto szPref = dst.size is 16;
    auto rexW = dst.size is 64;

    cb.writeRMInstr!('r', 0xFF, 0x0F, opcode1)(szPref, rexW, X86Opnd(dst), src);
}
*/

// add - Integer addition
void add(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_rm_multi(
        cb,
        "add",
        0x00, // opMemReg8
        0x01, // opMemRegPref
        0x02, // opRegMem8
        0x03, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        0x00, // opExtImm
        opnd0,
        opnd1
    );
}

/// and - Bitwise AND
void and(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_rm_multi(
        cb,
        "and",
        0x20, // opMemReg8
        0x21, // opMemRegPref
        0x22, // opRegMem8
        0x23, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        0x04, // opExtImm
        opnd0,
        opnd1
    );
}

/// call - Call to label with 32-bit offset
void call_label(codeblock_t* cb, size_t label_idx)
{
    //cb.writeASM("call", label);

    // Write the opcode
    cb_write_byte(cb, 0xE8);

    // Add a reference to the label
    cb_label_ref(cb, label_idx);

    // Relative 32-bit offset to be patched
    cb_write_int(cb, 0, 32);
}

/// call - Indirect call with an R/M operand
void call(codeblock_t* cb, x86opnd_t opnd)
{
    //cb.writeASM("call", opnd);
    cb_write_rm(cb, false, false, NO_OPND, opnd, 2, 1, 0xFF);
}

/*
/// cmovcc - Conditional move
alias cmova = writeCmov!("cmova", 0x47);
alias cmovae = writeCmov!("cmovae", 0x43);
alias cmovb = writeCmov!("cmovb", 0x42);
alias cmovbe = writeCmov!("cmovbe", 0x46);
alias cmovc = writeCmov!("cmovc", 0x42);
alias cmove = writeCmov!("cmove", 0x44);
alias cmovg = writeCmov!("cmovg", 0x4F);
alias cmovge = writeCmov!("cmovge", 0x4D);
alias cmovl = writeCmov!("cmovl", 0x4C);
alias cmovle = writeCmov!("cmovle", 0x4E);
alias cmovna = writeCmov!("cmovna", 0x46);
alias cmovnae = writeCmov!("cmovnae", 0x42);
alias cmovnb = writeCmov!("cmovnb", 0x43);
alias cmovnbe = writeCmov!("cmovnbe", 0x47);
alias cmovnc = writeCmov!("cmovnc", 0x43);
alias cmovne = writeCmov!("cmovne", 0x45);
alias cmovnge = writeCmov!("cmovng", 0x4E);
alias cmovnge = writeCmov!("cmovnge", 0x4C);
alias cmovnl = writeCmov!("cmovnl", 0x4D);
alias cmovnle = writeCmov!("cmovnle", 0x4F);
alias cmovno = writeCmov!("cmovno", 0x41);
alias cmovnp = writeCmov!("cmovnp", 0x4B);
alias cmovns = writeCmov!("cmovns", 0x49);
alias cmovnz = writeCmov!("cmovnz", 0x45);
alias cmovo = writeCmov!("cmovno", 0x40);
alias cmovp = writeCmov!("cmovp", 0x4A);
alias cmovpe = writeCmov!("cmovpe", 0x4A);
alias cmovpo = writeCmov!("cmovpo", 0x4B);
alias cmovs = writeCmov!("cmovs", 0x48);
alias cmovz = writeCmov!("cmovz", 0x44);
*/

/// cmp - Compare and set flags
void cmp(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_rm_multi(
        cb,
        "cmp",
        0x38, // opMemReg8
        0x39, // opMemRegPref
        0x3A, // opRegMem8
        0x3B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        0x07, // opExtImm
        opnd0,
        opnd1
    );
}

/// cdq - Convert doubleword to quadword
void cdq(codeblock_t* cb)
{
    //cb.writeASM("cdq");
    cb_write_byte(cb, 0x99);
}

/// cqo - Convert quadword to octaword
void cqo(codeblock_t* cb)
{
    //cb.writeASM("cqo");
    cb_write_bytes(cb, 2, 0x48, 0x99);
}

// dec - Decrement integer by 1
void dec(codeblock_t* cb, x86opnd_t opnd)
{
    write_rm_unary(
        cb,
        "dec",
        0xFE, // opMemReg8
        0xFF, // opMemRegPref
        0x01, // opExt
        opnd
    );
}

/*
// div - Unsigned integer division
alias div = writeRMUnary!(
    "div",
    0xF6, // opMemReg8
    0xF7, // opMemRegPref
    0x06  // opExt
);
*/

/*
/// divsd - Divide scalar double
alias divsd = writeXMM64!(
    "divsd",
    0xF2, // prefix
    0x0F, // opRegMem0
    0x5E  // opRegMem1
);
*/

/*
// idiv - Signed integer division
alias idiv = writeRMUnary!(
    "idiv",
    0xF6, // opMemReg8
    0xF7, // opMemRegPref
    0x07  // opExt
);
*/

/*
/// imul - Signed integer multiplication with two operands
void imul(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1)
{
    cb.writeASM("imul", opnd0, opnd1);

    assert (opnd0.isReg, "invalid first operand");
    auto opndSize = opnd0.reg.size;

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch");

    assert (opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    cb.writeRMInstr!('r', 0xFF, 0x0F, 0xAF)(szPref, rexW, opnd0, opnd1);
}
*/

/*
/// imul - Signed integer multiplication with three operands (one immediate)
void imul(CodeBlock cb, X86Opnd opnd0, X86Opnd opnd1, X86Opnd opnd2)
{
    cb.writeASM("imul", opnd0, opnd1, opnd2);

    assert (opnd0.isReg, "invalid first operand");
    auto opndSize = opnd0.reg.size;

    // Check the size of opnd1
    if (opnd1.isReg)
        assert (opnd1.reg.size is opndSize, "operand size mismatch");
    else if (opnd1.isMem)
        assert (opnd1.mem.size is opndSize, "operand size mismatch");

    assert (opndSize is 16 || opndSize is 32 || opndSize is 64);
    auto szPref = opndSize is 16;
    auto rexW = opndSize is 64;

    assert (opnd2.isImm, "invalid third operand");
    auto imm = opnd2.imm;

    // 8-bit immediate
    if (imm.immSize <= 8)
    {
        cb.writeRMInstr!('r', 0xFF, 0x6B)(szPref, rexW, opnd0, opnd1);
        cb.writeInt(imm.imm, 8);
    }

    // 32-bit immediate
    else if (imm.immSize <= 32)
    {
        assert (imm.immSize <= opndSize, "immediate too large for dst");
        cb.writeRMInstr!('r', 0xFF, 0x69)(szPref, rexW, opnd0, opnd1);
        cb.writeInt(imm.imm, min(opndSize, 32));
    }

    // Immediate too large
    else
    {
        assert (false, "immediate value too large");
    }
}
*/

// inc - Increment integer by 1
void inc(codeblock_t* cb, x86opnd_t opnd)
{
    write_rm_unary(
        cb,
        "inc",
        0xFE, // opMemReg8
        0xFF, // opMemRegPref
        0x00, // opExt
        opnd
    );
}

/// jcc - Conditional relative jump to a label
void ja  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "ja"  , 0x0F, 0x87, label_idx); }
void jae (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jae" , 0x0F, 0x83, label_idx); }
void jb  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jb"  , 0x0F, 0x82, label_idx); }
void jbe (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jbe" , 0x0F, 0x86, label_idx); }
void jc  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jc"  , 0x0F, 0x82, label_idx); }
void je  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "je"  , 0x0F, 0x84, label_idx); }
void jg  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jg"  , 0x0F, 0x8F, label_idx); }
void jge (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jge" , 0x0F, 0x8D, label_idx); }
void jl  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jl"  , 0x0F, 0x8C, label_idx); }
void jle (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jle" , 0x0F, 0x8E, label_idx); }
void jna (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jna" , 0x0F, 0x86, label_idx); }
void jnae(codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnae", 0x0F, 0x82, label_idx); }
void jnb (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnb" , 0x0F, 0x83, label_idx); }
void jnbe(codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnbe", 0x0F, 0x87, label_idx); }
void jnc (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnc" , 0x0F, 0x83, label_idx); }
void jne (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jne" , 0x0F, 0x85, label_idx); }
void jng (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jng" , 0x0F, 0x8E, label_idx); }
void jnge(codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnge", 0x0F, 0x8C, label_idx); }
void jnl (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnl" , 0x0F, 0x8D, label_idx); }
void jnle(codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnle", 0x0F, 0x8F, label_idx); }
void jno (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jno" , 0x0F, 0x81, label_idx); }
void jnp (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnp" , 0x0F, 0x8b, label_idx); }
void jns (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jns" , 0x0F, 0x89, label_idx); }
void jnz (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jnz" , 0x0F, 0x85, label_idx); }
void jo  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jo"  , 0x0F, 0x80, label_idx); }
void jp  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jp"  , 0x0F, 0x8A, label_idx); }
void jpe (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jpe" , 0x0F, 0x8A, label_idx); }
void jpo (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jpo" , 0x0F, 0x8B, label_idx); }
void js  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "js"  , 0x0F, 0x88, label_idx); }
void jz  (codeblock_t* cb, size_t label_idx) { cb_write_jcc(cb, "jz"  , 0x0F, 0x84, label_idx); }

/// jmp - Direct relative jump to label
void jmp(codeblock_t* cb, size_t label_idx)
{
    //cb.writeASM(mnem, label);

    /// Opcode for direct jump with relative 32-bit offset
    cb_write_byte(cb, 0xE9);

    // Add a reference to the label
    cb_label_ref(cb, label_idx);

    // Relative 32-bit offset to be patched
    cb_write_int(cb, 0, 32);
}

/// jmp - Indirect jump near to an R/M operand
void jmp_rm(codeblock_t* cb, x86opnd_t opnd)
{
    //cb.writeASM("jmp", opnd);
    cb_write_rm(cb, false, false, NO_OPND, opnd, 4, 1, 0xFF);
}

/*
/// Opcode for direct jump with relative 8-bit offset
const ubyte JMP_REL8_OPCODE = 0xEB;
*/

/*
/// jmp - Jump with relative 8-bit offset
void jmp8(CodeBlock cb, int8_t offset)
{
    cb.writeASM("jmp", ((offset > 0)? "+":"-") ~ to!string(offset));
    cb.writeByte(JMP_REL8_OPCODE);
    cb.writeByte(offset);
}
*/

/*
/// jmp - Jump with relative 32-bit offset
void jmp32(CodeBlock cb, int32_t offset)
{
    cb.writeASM("jmp", ((offset > 0)? "+":"-") ~ to!string(offset));
    cb.writeByte(JMP_REL32_OPCODE);
    cb.writeInt(offset, 32);
}
*/

/// lea - Load Effective Address
void lea(codeblock_t* cb, x86opnd_t dst, x86opnd_t src)
{
    //cb.writeASM("lea", dst, src);
    assert (dst.num_bits == 64);
    cb_write_rm(cb, false, true, dst, src, 0xFF, 1, 0x8D);
}

/// mov - Data move operation
void mov(codeblock_t* cb, x86opnd_t dst, x86opnd_t src)
{
    // R/M + Imm
    if (src.type == OPND_IMM)
    {
        //cb.writeASM("mov", dst, src);

        // R + Imm
        if (dst.type == OPND_REG)
        {
            assert (
                src.num_bits <= dst.num_bits ||
                unsig_imm_size(src.imm) <= dst.num_bits
            );

            if (dst.num_bits == 16)
                cb_write_byte(cb, 0x66);
            if (rex_needed(src) || dst.num_bits == 64)
                cb_write_rex(cb, dst.num_bits == 64, 0, 0, dst.reg.reg_no);

            cb_write_opcode(cb, (dst.num_bits == 8)? 0xB0:0xB8, dst);

            cb_write_int(cb, src.imm, dst.num_bits);
        }

        // M + Imm
        else if (dst.type == OPND_MEM)
        {
            assert (src.num_bits <= dst.num_bits);

            if (dst.num_bits == 8)
                cb_write_rm(cb, false, false, NO_OPND, dst, 0xFF, 1, 0xC6);
            else
                cb_write_rm(cb, dst.num_bits == 16, dst.num_bits == 64, NO_OPND, dst, 0, 1, 0xC7);

            cb_write_int(cb, src.imm, (dst.num_bits > 32)? 32:dst.num_bits);
        }

        else
        {
            assert (false);
        }
    }
    else
    {
        cb_write_rm_multi(
            cb,
            "mov",
            0x88, // opMemReg8
            0x89, // opMemRegPref
            0x8A, // opRegMem8
            0x8B, // opRegMemPref
            0xC6, // opMemImm8
            0xFF, // opMemImmSml (not available)
            0xFF, // opMemImmLrg
            0xFF,  // opExtImm
            dst,
            src
        );
    }
}

// neg - Integer negation (multiplication by -1)
void neg(codeblock_t* cb, x86opnd_t opnd)
{
    write_rm_unary(
        cb,
        "neg",
        0xF6, // opMemReg8
        0xF7, // opMemRegPref
        0x03,  // opExt
        opnd
    );
}

// nop - Noop, one or multiple bytes long
void nop(codeblock_t* cb, size_t length)
{
    switch (length)
    {
        case 0:
        break;

        case 1:
        //cb.writeASM("nop1");
        cb_write_byte(cb, 0x90);
        break;

        case 2:
        //cb.writeASM("nop2");
        cb_write_bytes(cb, 2, 0x66,0x90);
        break;

        case 3:
        //cb.writeASM("nop3");
        cb_write_bytes(cb, 3, 0x0F,0x1F,0x00);
        break;

        case 4:
        //cb.writeASM("nop4");
        cb_write_bytes(cb, 4, 0x0F,0x1F,0x40,0x00);
        break;

        case 5:
        //cb.writeASM("nop5");
        cb_write_bytes(cb, 5, 0x0F,0x1F,0x44,0x00,0x00);
        break;

        case 6:
        //cb.writeASM("nop6");
        cb_write_bytes(cb, 6, 0x66,0x0F,0x1F,0x44,0x00,0x00);
        break;

        case 7:
        //cb.writeASM("nop7");
        cb_write_bytes(cb, 7, 0x0F,0x1F,0x80,0x00,0x00,0x00,0x00);
        break;

        case 8:
        //cb.writeASM("nop8");
        cb_write_bytes(cb, 8, 0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00);
        break;

        case 9:
        //cb.writeASM("nop9");
        cb_write_bytes(cb, 9, 0x66,0x0F,0x1F,0x84,0x00,0x00,0x00,0x00,0x00);
        break;

        default:
        {
            size_t written = 0;
            while (written + 9 <= length)
            {
                nop(cb, 9);
                written += 9;
            }
            nop(cb, length - written);
        }
        break;
    }
}

// not - Bitwise NOT
void not(codeblock_t* cb, x86opnd_t opnd)
{
    write_rm_unary(
        cb,
        "not",
        0xF6, // opMemReg8
        0xF7, // opMemRegPref
        0x02, // opExt
        opnd
    );
}

/// or - Bitwise OR
void or(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_rm_multi(
        cb,
        "or",
        0x08, // opMemReg8
        0x09, // opMemRegPref
        0x0A, // opRegMem8
        0x0B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        0x01, // opExtImm
        opnd0,
        opnd1
    );
}

/// pop - Pop a register off the stack
void pop(codeblock_t* cb, x86opnd_t reg)
{
    assert (reg.num_bits == 64);

    //cb.writeASM("pop", reg);

    if (rex_needed(reg))
        cb_write_rex(cb, false, 0, 0, reg.reg.reg_no);

    cb_write_opcode(cb, 0x58, reg);
}

/// push - Push a register on the stack
void push(codeblock_t* cb, x86opnd_t reg)
{
    assert (reg.num_bits == 64);

    //cb.writeASM("push", reg);

    if (rex_needed(reg))
        cb_write_rex(cb, false, 0, 0, reg.reg.reg_no);

    cb_write_opcode(cb, 0x50, reg);
}

/// ret - Return from call, popping only the return address
void ret(codeblock_t* cb)
{
    //cb.writeASM("ret");
    cb_write_byte(cb, 0xC3);
}

// sal - Shift arithmetic left
void sal(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_shift(
        cb,
        "sal",
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// sar - Shift arithmetic right (signed)
void sar(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_shift(
        cb,
        "sar",
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x07,
        opnd0,
        opnd1
    );
}
// shl - Shift logical left
void shl(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_shift(
        cb,
        "shl",
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x04,
        opnd0,
        opnd1
    );
}

/// shr - Shift logical right (unsigned)
void shr(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_shift(
        cb,
        "shr",
        0xD1, // opMemOnePref,
        0xD3, // opMemClPref,
        0xC1, // opMemImmPref,
        0x05,
        opnd0,
        opnd1
    );
}

/// sub - Integer subtraction
void sub(codeblock_t* cb, x86opnd_t opnd0, x86opnd_t opnd1)
{
    cb_write_rm_multi(
        cb,
        "sub",
        0x28, // opMemReg8
        0x29, // opMemRegPref
        0x2A, // opRegMem8
        0x2B, // opRegMemPref
        0x80, // opMemImm8
        0x83, // opMemImmSml
        0x81, // opMemImmLrg
        0x05, // opExtImm
        opnd0,
        opnd1
    );
}

/*
/// xor - Exclusive bitwise OR
alias xor = writeRMMulti!(
    "xor",
    0x30, // opMemReg8
    0x31, // opMemRegPref
    0x32, // opRegMem8
    0x33, // opRegMemPref
    0x80, // opMemImm8
    0x83, // opMemImmSml
    0x81, // opMemImmLrg
    0x06  // opExtImm
);
*/
