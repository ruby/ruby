/* Functions and variables that are used by more than one source file of
 * the kernel.  Not available to extensions and applications.
 */

/* array.c */
void memclear _((register VALUE *, register int));
VALUE assoc_new _((VALUE, VALUE));
VALUE ary_new _((void));
VALUE ary_new2 _((int));
VALUE ary_new3();
VALUE ary_new4 _((int, VALUE *));
VALUE ary_freeze _((VALUE));
void ary_store _((VALUE, int, VALUE));
VALUE ary_push _((VALUE, VALUE));
VALUE ary_pop _((VALUE));
VALUE ary_shift _((VALUE));
VALUE ary_unshift _((VALUE, VALUE));
VALUE ary_entry _((VALUE, int));
VALUE ary_each _((VALUE));
VALUE ary_join _((VALUE, VALUE));
VALUE ary_to_s _((VALUE));
VALUE ary_print_on _((VALUE, VALUE));
VALUE ary_reverse _((VALUE));
VALUE ary_sort_bang _((VALUE));
VALUE ary_sort _((VALUE));
VALUE ary_delete _((VALUE, VALUE));
VALUE ary_delete_at _((VALUE, VALUE));
VALUE ary_plus _((VALUE, VALUE));
VALUE ary_concat _((VALUE, VALUE));
VALUE ary_assoc _((VALUE, VALUE));
VALUE ary_rassoc _((VALUE, VALUE));
VALUE ary_includes _((VALUE, VALUE));
/* bignum.c */
VALUE big_clone _((VALUE));
void big_2comp _((VALUE));
VALUE big_norm _((VALUE));
VALUE uint2big _((UINT));
VALUE int2big _((INT));
VALUE uint2inum _((UINT));
VALUE int2inum _((INT));
VALUE str2inum _((UCHAR *, int));
VALUE big2str _((VALUE, int));
INT big2int _((VALUE));
VALUE big_to_i _((VALUE));
VALUE dbl2big _((double));
double big2dbl _((VALUE));
VALUE big_to_f _((VALUE));
VALUE big_plus _((VALUE, VALUE));
VALUE big_minus _((VALUE, VALUE));
VALUE big_mul _((VALUE, VALUE));
VALUE big_pow _((VALUE, VALUE));
VALUE big_and _((VALUE, VALUE));
VALUE big_or _((VALUE, VALUE));
VALUE big_xor _((VALUE, VALUE));
VALUE big_lshift _((VALUE, VALUE));
VALUE big_rand _((VALUE));
/* class.c */
VALUE class_new _((VALUE));
VALUE singleton_class_new _((VALUE));
VALUE singleton_class_clone _((VALUE));
void singleton_class_attached _((VALUE,VALUE));
VALUE rb_define_class_id _((ID, VALUE));
VALUE module_new _((void));
VALUE rb_define_module_id _((ID));
VALUE mod_included_modules _((VALUE));
VALUE mod_ancestors _((VALUE));
VALUE class_instance_methods _((int, VALUE *, VALUE));
VALUE class_private_instance_methods _((int, VALUE *, VALUE));
VALUE obj_singleton_methods _((VALUE));
void rb_define_method_id _((VALUE, ID, VALUE (*)(), int));
void rb_undef_method _((VALUE, char *));
void rb_define_protected_method _((VALUE, char *, VALUE (*)(), int));
void rb_define_private_method _((VALUE, char *, VALUE (*)(), int));
void rb_define_singleton_method _((VALUE,char*,VALUE(*)(),int));
void rb_define_private_method _((VALUE,char*,VALUE(*)(),int));
VALUE rb_singleton_class _((VALUE));
/* enum.c */
VALUE enum_length _((VALUE));
/* error.c */
VALUE exc_new _((VALUE, char *, UINT));
VALUE exc_new2 _((VALUE, char *));
VALUE exc_new3 _((VALUE, VALUE));
#ifdef __GNUC__
volatile voidfn TypeError;
volatile voidfn ArgError;
volatile voidfn NameError;
volatile voidfn IndexError;
volatile voidfn LoadError;
#else
void TypeError();
void ArgError();
void NameError();
void IndexError();
void LoadError();
#endif
/* eval.c */
void rb_remove_method _((VALUE, char *));
void rb_disable_super _((VALUE, char *));
void rb_enable_super _((VALUE, char *));
void rb_clear_cache _((void));
void rb_alias _((VALUE, ID, ID));
void rb_attr _((VALUE,ID,int,int,int));
int rb_method_boundp _((VALUE, ID, int));
VALUE dyna_var_defined _((ID));
VALUE dyna_var_ref _((ID));
VALUE dyna_var_asgn _((ID, VALUE));
void ruby_init _((void));
void ruby_options _((int, char **));
void ruby_run _((void));
void rb_eval_cmd _((VALUE, VALUE));
void rb_trap_eval _((VALUE, int));
int rb_respond_to _((VALUE, ID));
void rb_raise _((VALUE));
void rb_fatal _((VALUE));
void rb_interrupt _((void));
int iterator_p _((void));
VALUE rb_yield_0 _((VALUE, volatile VALUE));
VALUE rb_apply _((VALUE, ID, VALUE));
VALUE rb_funcall2 _((VALUE, ID, int, VALUE *));
void rb_backtrace _((void));
ID rb_frame_last_func _((void));
VALUE f_load _((VALUE, VALUE));
void rb_provide _((char *));
VALUE f_require _((VALUE, VALUE));
void obj_call_init _((VALUE));
VALUE class_new_instance _((int, VALUE *, VALUE));
VALUE f_lambda _((void));
void rb_set_end_proc _((void (*)(),VALUE));
void gc_mark_threads _((void));
void thread_schedule _((void));
void thread_wait_fd _((int));
void thread_fd_writable _((int));
int thread_alone _((void));
void thread_sleep _((int));
void thread_sleep_forever _((void));
VALUE thread_create _((VALUE (*)(), void *));
void thread_interrupt _((void));
void thread_trap_eval _((VALUE, int));
/* file.c */
VALUE file_open _((char *, char *));
int eaccess _((char *, int));
VALUE file_s_expand_path _((VALUE, VALUE));
/* gc.c */
void rb_global_variable _((VALUE *));
void gc_mark_locations _((VALUE *, VALUE *));
void gc_mark_maybe();
void gc_mark();
void gc_force_recycle();
void gc_gc _((void));
void init_stack _((void));
void init_heap _((void));
/* hash.c */
VALUE hash_freeze _((VALUE));
VALUE rb_hash _((VALUE));
VALUE hash_new _((void));
VALUE hash_aref _((VALUE, VALUE));
VALUE hash_aset _((VALUE, VALUE, VALUE));
/* io.c */
void eof_error _((void));
VALUE io_write _((VALUE, VALUE));
VALUE io_gets_method _((int, VALUE*, VALUE));
VALUE io_gets _((VALUE));
VALUE io_getc _((VALUE));
VALUE io_ungetc _((VALUE, VALUE));
VALUE io_close _((VALUE));
VALUE io_binmode _((VALUE));
int io_mode_flags _((char *));
VALUE io_reopen _((VALUE, VALUE));
VALUE f_gets _((void));
void rb_str_setter _((VALUE, ID, VALUE *));
/* numeric.c */
void num_zerodiv _((void));
VALUE num_coerce_bin _((VALUE, VALUE));
VALUE float_new _((double));
VALUE flo_pow _((VALUE, VALUE));
VALUE num2fix _((VALUE));
VALUE fix2str _((VALUE, int));
VALUE fix_to_s _((VALUE));
VALUE num_upto _((VALUE, VALUE));
VALUE fix_upto _((VALUE, VALUE));
/* object.c */
VALUE rb_equal _((VALUE, VALUE));
int rb_eql _((VALUE, VALUE));
VALUE obj_equal _((VALUE, VALUE));
VALUE any_to_s _((VALUE));
VALUE rb_inspect _((VALUE));
VALUE obj_is_instance_of _((VALUE, VALUE));
VALUE obj_is_kind_of _((VALUE, VALUE));
VALUE obj_alloc _((VALUE));
VALUE rb_convert_type _((VALUE,int,char*,char*));
VALUE rb_Integer _((VALUE));
VALUE rb_Float _((VALUE));
VALUE rb_String _((VALUE));
VALUE rb_Array _((VALUE));
double num2dbl _((VALUE));
/* parse.y */
int yyparse _((void));
void pushback _((int));
ID id_attrset _((ID));
void yyappend_print _((void));
void yywhile_loop _((int, int));
int rb_is_const_id _((ID));
int rb_is_instance_id _((ID));
void local_var_append _((ID));
VALUE backref_get _((void));
void backref_set _((VALUE));
VALUE lastline_get _((void));
void lastline_set _((VALUE));
/* process.c */
int rb_proc_exec _((char *));
void rb_syswait _((int));
/* range.c */
VALUE range_new _((VALUE, VALUE));
VALUE range_beg_end _((VALUE, int *, int *));
/* re.c */
VALUE reg_nth_defined _((int, VALUE));
VALUE reg_nth_match _((int, VALUE));
VALUE reg_last_match _((VALUE));
VALUE reg_match_pre _((VALUE));
VALUE reg_match_post _((VALUE));
VALUE reg_match_last _((VALUE));
VALUE reg_new _((char *, int, int));
VALUE reg_match _((VALUE, VALUE));
VALUE reg_match2 _((VALUE));
char*rb_get_kcode _((void));
void rb_set_kcode _((char *));
/* ruby.c */
void rb_load_file _((char *));
void ruby_script _((char *));
void ruby_prog_init _((void));
void ruby_set_argv _((int, char **));
void ruby_process_options _((int, char **));
void ruby_require_modules _((void));
void ruby_load_script _((void));
/* signal.c */
VALUE f_kill _((int, VALUE *));
void gc_mark_trap_list _((void));
void posix_signal _((int, void (*)()));
void rb_trap_exit _((void));
void rb_trap_exec _((void));
/* sprintf.c */
VALUE f_sprintf _((int, VALUE *));
/* string.c */
VALUE str_new _((UCHAR *, UINT));
VALUE str_new2 _((UCHAR *));
VALUE str_new3 _((VALUE));
VALUE str_new4 _((VALUE));
VALUE obj_as_string _((VALUE));
VALUE str_to_str _((VALUE));
VALUE str_dup _((VALUE));
VALUE str_plus _((VALUE, VALUE));
VALUE str_times _((VALUE, VALUE));
VALUE str_substr _((VALUE, int, int));
void str_modify _((VALUE));
VALUE str_freeze _((VALUE));
VALUE str_dup_frozen _((VALUE));
VALUE str_taint _((VALUE));
VALUE str_tainted _((VALUE));
VALUE str_resize _((VALUE, int));
VALUE str_cat _((VALUE, UCHAR *, UINT));
int str_hash _((VALUE));
int str_cmp _((VALUE, VALUE));
VALUE str_upto _((VALUE, VALUE));
VALUE str_inspect _((VALUE));
VALUE str_split _((VALUE, char *));
/* struct.c */
VALUE struct_new();
VALUE struct_define();
VALUE struct_alloc _((VALUE, VALUE));
VALUE struct_aref _((VALUE, VALUE));
VALUE struct_aset _((VALUE, VALUE, VALUE));
VALUE struct_getmember _((VALUE, ID));
/* time.c */
VALUE time_new _((int, int));
/* util.c */
void add_suffix _((VALUE, char *));
unsigned long scan_oct _((char *, int, int *));
unsigned long scan_hex _((char *, int, int *));
/* variable.c */
VALUE mod_name _((VALUE));
VALUE rb_class_path _((VALUE));
void rb_set_class_path _((VALUE, VALUE, char *));
VALUE rb_path2class _((char *));
void rb_name_class _((VALUE, ID));
void rb_autoload _((char *, char *));
VALUE f_autoload _((VALUE, VALUE, VALUE));
void gc_mark_global_tbl _((void));
VALUE f_trace_var _((int, VALUE *));
VALUE f_untrace_var _((int, VALUE *));
VALUE rb_gvar_set2 _((char *, VALUE));
VALUE f_global_variables _((void));
void rb_alias_variable _((ID, ID));
VALUE rb_ivar_get _((VALUE, ID));
VALUE rb_ivar_set _((VALUE, ID, VALUE));
VALUE rb_ivar_defined _((VALUE, ID));
VALUE obj_instance_variables _((VALUE));
VALUE mod_const_at _((VALUE, VALUE));
VALUE mod_constants _((VALUE));
VALUE mod_const_of _((VALUE, VALUE));
int rb_const_defined_at _((VALUE, ID));
int rb_autoload_defined _((ID));
int rb_const_defined _((VALUE, ID));
