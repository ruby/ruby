# -*- Autoconf -*-
AC_DEFUN([RUBY_STACK_GROW_DIRECTION], [
    AS_VAR_PUSHDEF([stack_grow_dir], [rb_cv_stack_grow_dir_$1])
    AC_CACHE_CHECK(stack growing direction on $1, stack_grow_dir, [
AS_CASE(["$1"],
[m68*|x86*|x64|i?86|ppc*|sparc*|alpha*], [ $2=-1],
[hppa*], [ $2=+1],
[
  AC_TRY_RUN([
/* recurse to get rid of inlining */
static int
stack_growup_p(addr, n)
    volatile int *addr, n;
{
    volatile int end;
    if (n > 0)
	return *addr = stack_growup_p(addr, n - 1);
    else
	return (&end > addr);
}
int main()
{
    int x;
    return stack_growup_p(&x, 10);
}
], $2=-1, $2=+1, $2=0)
  ])
eval stack_grow_dir=\$$2])
eval $2=\$stack_grow_dir
AS_VAR_POPDEF([stack_grow_dir])])dnl
