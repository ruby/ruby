/**********************************************************************

  ruby/vm.h -

  $Author$
  created at: Sat May 31 15:17:36 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_VM_H
#define RUBY_VM_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

/* Place holder.
 *
 * We will prepare VM creation/control APIs on 1.9.2 or later.
 * If you have an interest about it, please see mvm branch.
 * http://svn.ruby-lang.org/cgi-bin/viewvc.cgi/branches/mvm/
 */

/* VM type declaration */
typedef struct rb_vm_struct ruby_vm_t;

/* core API */
int ruby_vm_destruct(ruby_vm_t *vm);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_VM_H */
