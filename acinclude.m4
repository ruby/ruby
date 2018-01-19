# -*- autoconf -*-

dnl inclusion order matters
dnl because they depend each other
m4_include([tool/m4/_colorize_result_prepare.m4])dnl
m4_include([tool/m4/colorize_result.m4])dnl
m4_include([tool/m4/ac_checking.m4])dnl
m4_include([tool/m4/ac_msg_result.m4])dnl
m4_include([tool/m4/ruby_rm_recursive.m4])dnl
m4_include([tool/m4/ruby_mingw32.m4])dnl
m4_include([tool/m4/ruby_cppoutfile.m4])dnl
m4_include([tool/m4/ruby_prog_gnu_ld.m4])dnl
m4_include([tool/m4/ruby_append_option.m4])dnl
m4_include([tool/m4/ruby_append_options.m4])dnl
m4_include([tool/m4/ruby_prepend_option.m4])dnl
m4_include([tool/m4/ruby_prepend_options.m4])dnl
m4_include([tool/m4/ruby_default_arch.m4])dnl
m4_include([tool/m4/ruby_universal_arch.m4])dnl
m4_include([tool/m4/ruby_dtrace_available.m4])dnl
m4_include([tool/m4/ruby_dtrace_postprocess.m4])dnl
m4_include([tool/m4/ruby_werror_flag.m4])dnl
m4_include([tool/m4/ruby_try_cflags.m4])dnl
m4_include([tool/m4/ruby_try_ldflags.m4])dnl
m4_include([tool/m4/ruby_check_sizeof.m4])dnl
m4_include([tool/m4/ruby_check_printf_prefix.m4])dnl
m4_include([tool/m4/ruby_check_signedness.m4])dnl
m4_include([tool/m4/ruby_replace_type.m4])dnl
m4_include([tool/m4/ruby_define_if.m4])dnl
m4_include([tool/m4/ruby_decl_attribute.m4])dnl
m4_include([tool/m4/ruby_func_attribute.m4])dnl
m4_include([tool/m4/ruby_type_attribute.m4])dnl
m4_include([tool/m4/ruby_defint.m4])dnl
m4_include([tool/m4/ruby_check_builtin_func.m4])dnl
m4_include([tool/m4/ruby_check_setjmp.m4])dnl
m4_include([tool/m4/ruby_check_builtin_setjmp.m4])dnl
m4_include([tool/m4/ruby_setjmp_type.m4])dnl
m4_include([tool/m4/ruby_check_sysconf.m4])dnl
m4_include([tool/m4/ruby_stack_grow_direction.m4])dnl
