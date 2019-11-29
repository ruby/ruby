#ifndef INTERNAL_COMPILE_H /* -*- C -*- */
#define INTERNAL_COMPILE_H
/**
 * @file
 * @brief      Internal header for the compiler.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* compile.c */
struct rb_block;
struct rb_iseq_struct;
int rb_dvar_defined(ID, const struct rb_iseq_struct *);
int rb_local_defined(ID, const struct rb_iseq_struct *);
const char * rb_insns_name(int i);
VALUE rb_insns_name_array(void);
int rb_vm_insn_addr2insn(const void *);

#endif /* INTERNAL_COMPILE_H */
