#ifndef UJIT_ASM_H
#define UJIT_ASM_H 1

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Maximum number of labels to link
#define MAX_LABELS 32

// Maximum number of label references
#define MAX_LABEL_REFS 32

typedef struct LabelRef
{
    // Position where the label reference is in the code block
    size_t pos;

    // Label which this refers to
    size_t label_idx;

} labelref_t;

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

typedef struct X86Opnd
{




} x86opnd_t;

void cb_init(codeblock_t* cb, size_t mem_size);
uint8_t* cb_get_ptr(codeblock_t* cb, size_t index);
void cb_write_byte(codeblock_t* cb, uint8_t byte);
void cb_write_bytes(codeblock_t* cb, size_t num_bytes, ...);
void cb_write_int(codeblock_t* cb, uint64_t val, size_t num_bits);

// Ruby instruction prologue and epilogue functions
void cb_write_prologue(codeblock_t* cb);
void cb_write_epilogue(codeblock_t* cb);

void nop(codeblock_t* cb, size_t length);





#endif
