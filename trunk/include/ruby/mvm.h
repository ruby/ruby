/**********************************************************************

  ruby/mvm.h -

  $Author$
  created at: Sat May 31 15:17:36 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_MVM_H
#define RUBY_MVM_H 1

typedef struct rb_vm_struct rb_vm_t;
typedef struct rb_thread_struct rb_thread_t;

VALUE *ruby_vm_verbose_ptr(rb_vm_t *);
VALUE *ruby_vm_debug_ptr(rb_vm_t *);

#endif /* RUBY_MVM_H */
