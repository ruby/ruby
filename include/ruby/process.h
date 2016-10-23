/**********************************************************************

  process.h -

  $Author$
  created at: Sun Oct 23 11:48:04 JST 2016

  Copyright (C) 2016 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_PROCESS_H
#define RUBY_PROCESS_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

struct rb_execarg;
typedef int ruby_fork_child_func(void*, char *, size_t);

int rb_exec_async_signal_safe(const struct rb_execarg *e, char *errmsg, size_t errmsg_buflen);
rb_pid_t rb_fork_async_signal_safe(int *status, ruby_fork_child_func *chfunc, void *charg, VALUE fds, char *errmsg, size_t errmsg_buflen);
VALUE rb_execarg_new(int argc, const VALUE *argv, int accept_shell);
struct rb_execarg *rb_execarg_get(VALUE execarg_obj); /* dangerous.  needs GC guard. */
VALUE rb_execarg_init(int argc, const VALUE *argv, int accept_shell, VALUE execarg_obj);
int rb_execarg_addopt(VALUE execarg_obj, VALUE key, VALUE val);
void rb_execarg_parent_start(VALUE execarg_obj);
void rb_execarg_parent_end(VALUE execarg_obj);
int rb_execarg_run_options(const struct rb_execarg *e, struct rb_execarg *s, char* errmsg, size_t errmsg_buflen);
VALUE rb_execarg_extract_options(VALUE execarg_obj, VALUE opthash);
void rb_execarg_setenv(VALUE execarg_obj, VALUE env);

RUBY_SYMBOL_EXPORT_END

#endif	/* RUBY_PROCESS_H */
