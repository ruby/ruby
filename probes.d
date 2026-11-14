/* -*- c -*- */
#include "vm_opts.h"

provider ruby {
  /*
     ruby:::method-entry(classname, methodname, filename, lineno);

     This probe is fired just before a method is entered.

     * `classname` name of the class (a string)
     * `methodname` name of the method about to be executed (a string)
     * `filename` the file name where the method is _being called_ (a string)
     * `lineno` the line number where the method is _being called_ (an int)
  */
  probe method__entry(const char *classname, const char *methodname, const char *filename, int lineno);
  /*
     ruby:::method-return(classname, methodname, filename, lineno);

     This probe is fired just after a method has returned. The arguments are
     the same as "ruby:::method-entry".
  */
  probe method__return(const char *classname, const char *methodname, const char *filename, int lineno);

  /*
     ruby:::cmethod-entry(classname, methodname, filename, lineno);

     This probe is fired just before a C method is entered. The arguments are
     the same as "ruby:::method-entry".
  */
  probe cmethod__entry(const char *classname, const char *methodname, const char *filename, int lineno);
  /*
     ruby:::cmethod-return(classname, methodname, filename, lineno);

     This probe is fired just before a C method returns. The arguments are
     the same as "ruby:::method-entry".
  */
  probe cmethod__return(const char *classname, const char *methodname, const char *filename, int lineno);

  /*
     ruby:::require-entry(requiredfile, filename, lineno);

     This probe is fired on calls to `rb_require_safe` (when a file is
     required).

     * `requiredfile` is the name of the file to be required (string).
     * `filename` is the file that called "require" (string).
     * `lineno` is the line number where the call to require was made (int).
  */
  probe require__entry(const char *rquiredfile, const char *filename, int lineno);

  /*
     ruby:::require-return(requiredfile, filename, lineno);

     This probe is fired just before `rb_require_safe` (when a file is required)
     returns.  The arguments are the same as "ruby:::require-entry".  This
     probe will not fire if there was an exception during file require.
  */
  probe require__return(const char *requiredfile, const char *filename, int lineno);

  /*
     ruby:::find-require-entry(requiredfile, filename, lineno);

     This probe is fired right before `search_required` is called.
     `search_required` determines whether the file has already been required by
     searching loaded features ($"), and if not, figures out which file must be
     loaded.

     * `requiredfile` is the file to be required (string).
     * `filename` is the file that called "require" (string).
     * `lineno` is the line number where the call to require was made (int).
  */
  probe find__require__entry(const char *requiredfile, const char *filename, int lineno);

  /*
     ruby:::find-require-return(requiredfile, filename, lineno);

     This probe is fired right after `search_required` returns.  See the
     documentation for "ruby:::find-require-entry" for more details.  Arguments
     for this probe are the same as "ruby:::find-require-entry".
  */
  probe find__require__return(const char *requiredfile, const char *filename, int lineno);

  /*
     ruby:::load-entry(loadedfile, filename, lineno);

     This probe is fired when calls to "load" are made.  The arguments are the
     same as "ruby:::require-entry".
  */
  probe load__entry(const char *loadedfile, const char *filename, int lineno);

  /*
     ruby:::load-return(loadedfile, filename, lineno);

     This probe is fired when "load" returns.  The arguments are the same as
     "ruby:::load-entry".
  */
  probe load__return(const char *loadedfile, const char *filename, int lineno);

  /*
     ruby:::raise(classname, filename, lineno);

     This probe is fired when an exception is raised.

     * `classname` is the class name of the raised exception (string)
     * `filename` the name of the file where the exception was raised (string)
     * `lineno` the line number in the file where the exception was raised (int)
  */
  probe raise(const char *classname, const char *filename, int lineno);

  /*
     ruby:::object-create(classname, filename, lineno);

     This probe is fired when an object is about to be allocated.

      * `classname` the class of the allocated object (string)
      * `filename` the name of the file where the object is allocated (string)
      * `lineno` the line number in the file where the object is allocated (int)
  */
  probe object__create(const char *classname, const char *filename, int lineno);

  /*
     ruby:::array-create(length, filename, lineno);

     This probe is fired when an Array is about to be allocated.

      * `length` the size of the array (long)
      * `filename` the name of the file where the array is allocated (string)
      * `lineno` the line number in the file where the array is allocated (int)
  */
  probe array__create(long length, const char *filename, int lineno);

  /*
     ruby:::hash-create(length, filename, lineno);

     This probe is fired when a Hash is about to be allocated.

      * `length` the size of the hash (long)
      * `filename` the name of the file where the hash is allocated (string)
      * `lineno` the line number in the file where the hash is allocated (int)
  */
  probe hash__create(long length, const char *filename, int lineno);

  /*
     ruby:::string-create(length, filename, lineno);

     This probe is fired when a String is about to be allocated.

      * `length` the size of the string (long)
      * `filename` the name of the file where the string is allocated (string)
      * `lineno` the line number in the file where the string is allocated (int)
  */
  probe string__create(long length, const char *filename, int lineno);

  /*
     ruby:::symbol-create(str, filename, lineno);

     This probe is fired when a Symbol is about to be allocated.

      * `str` the contents of the symbol (string)
      * `filename` the name of the file where the string is allocated (string)
      * `lineno` the line number in the file where the string is allocated (int)
  */
  probe symbol__create(const char *str, const char *filename, int lineno);

  /*
     ruby:::parse-begin(sourcefile, lineno);

     Fired just before parsing and compiling a source file.

     * `sourcefile` the file being parsed (string)
     * `lineno` the line number where the source starts (int)
  */
  probe parse__begin(const char *sourcefile, int lineno);

  /*
     ruby:::parse-end(sourcefile, lineno);

     Fired just after parsing and compiling a source file.

     * `sourcefile` the file being parsed (string)
     * `lineno` the line number where the source ended (int)
  */
  probe parse__end(const char *sourcefile, int lineno);

#if VM_COLLECT_USAGE_DETAILS
  probe insn(const char *insns_name);
  probe insn__operand(const char *val, const char *insns_name);
#endif

  /*
     ruby:::gc-mark-begin();

     Fired at the beginning of a mark phase.
  */
  probe gc__mark__begin();

  /*
     ruby:::gc-mark-end();

     Fired at the end of a mark phase.
  */
  probe gc__mark__end();

  /*
     ruby:::gc-sweep-begin();

     Fired at the beginning of a sweep phase.
  */
  probe gc__sweep__begin();

  /*
     ruby:::gc-sweep-end();

     Fired at the end of a sweep phase.
  */
  probe gc__sweep__end();

  /*
     ruby:::gc-enter(event);

     Fired when the `gc_enter` function in default.c is called.

     * `event` the `event` argument passed to gc_enter
  */
  probe gc__enter(int event);

  /*
     ruby:::gc-exit(event);

     Fired when the `gc_exit` function in default.c is called.

     * `event` the `event` argument passed to gc_exit
  */
  probe gc__exit(int event);

  /*
     ruby:::gc-mark-stacked-objects(popped_count);

     Fired for every invocation of `gc_mark_stacked_objects` in default.c.

     * `popped_count` the number of objects popped from the mark stack in that invocation
  */
  probe gc__mark_stacked_objects(size_t popped_count);

  /*
     ruby:::gc-sweep_page(slot_size, final_slots, freed_slots, empty_slots);

     Fired for every page swept in `gc_sweep_step` in default.c.

     * `slot_size` is the slot size of the page.
     * Other arguments are from the `gc_sweep_context` struct.
  */
  probe gc__sweep_page(int slot_size, int final_slots, int freed_slots, int empty_slots);

  /*
     ruby:::gc-obj_new();

     Fired when an object is allocated

     * `obj` the pointer to the allocated object
     * `flags` the initial flags of the object
  */
  probe gc__obj_new(void *obj, uintptr_t flags);

  /*
     ruby:::gc-obj_free();

     Fired when finalizing an object with `rb_gc_obj_free`.

     * `obj` the pointer to the finalized object
     * `flags` the flags of the object when it is finalized
  */
  probe gc__obj_free(void *obj, uintptr_t flags);

  /*
     ruby:::gc-xmalloc(n, size);

     Fired when allocating memory with `ruby_xmalloc` or `ruby_xmalloc2`.

     * `n` the number of elements.  For `ruby_xmalloc` it is 1.
     * `size` the size of each element
  */
  probe gc__xmalloc(size_t n, size_t size);

  /*
     ruby:::gc-xcalloc();

     Fired when allocating memory with `ruby_xcalloc`.

     * `n` the number of elements.  For `ruby_xmalloc` it is 1.
     * `size` the size of each element
  */
  probe gc__xcalloc(size_t n, size_t size);

  /*
     ruby:::gc-xfree(ptr, size);

     Fired when de-allocating memory with `ruby_xfree` or `ruby_xfree_sized`.

     * `ptr` the pointer to the object
     * `size` the size of the object.  0 if called with `xfree`
  */
  probe gc__xfree(void *obj, size_t size);

  /*
     ruby:::gvl-acquire();

     Fired the global VM lock is acquired
  */
  probe gvl__acquire();

  /*
     ruby:::gvl-release();

     Fired the global VM lock is release
  */
  probe gvl__release();

  /*
     ruby:::rts-set_running();

     Fired when setting the running thread of a Ractor (`rb_thread_sched::running`).

     This probe is mainly used to identify the duration in which a thread occupies a Ractor. If the
     `old_thread` is NULL and the `new_thread` is not NULL, it means the `new_thread` is scheduled
     onto a Ractor.  If the `old_thread` is not NULL but the `new_thread` is NULL, it means the
     `old_thread` is de-scheduled form a Ractor.

     * `sched` the `rb_thread_sched` instance
     * `old_thread` the old thread running on the ractor
     * `new_thread` the new thread running on the ractor
  */
  probe rts__set_running(void *sched, void *old_thread, void *new_thread);

  /*
     JIT invalidation probes.

     These are fired when a JIT throws away compiled code because an
     assumption it was compiled under no longer holds.  Each one corresponds
     to an invalidation counter in yjit/src/stats.rs or zjit/src/stats.rs.
     All of them take the same arguments:

     ruby:::yjit-invalidate_*(subject, count, filename, lineno);
     ruby:::zjit-invalidate_*(subject, count, filename, lineno);

     * `subject` what changed, e.g. "Integer#+" (a string, "" when there is
                 nothing more specific than the probe name)
     * `count` the amount of code invalidated (a long). For YJIT, this is the
               number of blocks, so the sum of `count` matches the
               corresponding counter (except for invalidate_everything,
               whose counter is the number of times it happened).  For ZJIT,
               this is the number of patch points.
     * `filename` the file name of the Ruby code that caused the
                  invalidation (a string)
     * `lineno` the line number of the Ruby code that caused the
                invalidation (an int)

     Except for yjit-invalidate_everything and zjit-invalidate_no_tracepoint,
     probes only fire when `count` is non-zero.
  */

  /*
     ruby:::yjit-invalidate_method_lookup(subject, count, filename, lineno);

     Fired when a method lookup YJIT depends on changes, e.g. because the
     method is redefined.  `subject` is the method, e.g. "Foo#bar".
  */
  probe yjit__invalidate_method_lookup(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_bop_redefined(subject, count, filename, lineno);

     Fired when a basic operator is redefined.  `subject` is the operator,
     e.g. "Integer#+".
  */
  probe yjit__invalidate_bop_redefined(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_ractor_spawn(subject, count, filename, lineno);

     Fired when a Ractor is spawned and code that assumes there is only one
     Ractor is invalidated.  `subject` is "".
  */
  probe yjit__invalidate_ractor_spawn(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_constant_state_bump(subject, count, filename, lineno);

     Fired when a constant is defined, redefined, or removed.  `subject` is
     the constant's name, e.g. "Foo".
  */
  probe yjit__invalidate_constant_state_bump(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_constant_ic_fill(subject, count, filename, lineno);

     Fired when an inline constant cache is filled.  `subject` is the
     constant path, e.g. "Foo::Bar".
  */
  probe yjit__invalidate_constant_ic_fill(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_no_singleton_class(subject, count, filename, lineno);

     Fired when a singleton class is created for an instance of a class that
     YJIT assumed had none.  `subject` is the class, e.g. "String".
  */
  probe yjit__invalidate_no_singleton_class(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_ep_escape(subject, count, filename, lineno);

     Fired when the environment of a method or block escapes to the heap.
     `subject` is the ISEQ, e.g. "foo@/path/to/file.rb:1".
  */
  probe yjit__invalidate_ep_escape(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::yjit-invalidate_everything(subject, count, filename, lineno);

     Fired when all YJIT code is invalidated, e.g. because a TracePoint is
     enabled.  `subject` is "".  Fired even when `count` is zero.
  */
  probe yjit__invalidate_everything(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_bop_redefined(subject, count, filename, lineno);

     Fired when a basic operator is redefined.  `subject` is the operator,
     e.g. "Integer#+".
  */
  probe zjit__invalidate_bop_redefined(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_method_redefined(subject, count, filename, lineno);

     Fired when a method lookup ZJIT depends on changes, e.g. because the
     method is redefined.  `subject` is the method, e.g. "Foo#bar".
  */
  probe zjit__invalidate_method_redefined(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_stable_constant_names(subject, count, filename, lineno);

     Fired when a constant is defined, redefined, or removed.  `subject` is
     the constant's name, e.g. "Foo".
  */
  probe zjit__invalidate_stable_constant_names(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_no_tracepoint(subject, count, filename, lineno);

     Fired when all ZJIT code is invalidated because a TracePoint is enabled.
     `subject` is "".  Fired even when `count` is zero.
  */
  probe zjit__invalidate_no_tracepoint(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_no_newobj_hook(subject, count, filename, lineno);

     Fired when a NEWOBJ internal event hook is enabled.  `subject` is "".
  */
  probe zjit__invalidate_no_newobj_hook(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_no_ep_escape(subject, count, filename, lineno);

     Fired when the environment of a method or block escapes to the heap.
     `subject` is the ISEQ, e.g. "foo@/path/to/file.rb:1".
  */
  probe zjit__invalidate_no_ep_escape(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_single_ractor_mode(subject, count, filename, lineno);

     Fired when a Ractor is spawned and code that assumes there is only one
     Ractor is invalidated.  `subject` is "".
  */
  probe zjit__invalidate_single_ractor_mode(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_no_singleton_class(subject, count, filename, lineno);

     Fired when a singleton class is created for an instance of a class that
     ZJIT assumed had none.  `subject` is the class, e.g. "String".
  */
  probe zjit__invalidate_no_singleton_class(const char *subject, long count, const char *filename, int lineno);

  /*
     ruby:::zjit-invalidate_root_box_only(subject, count, filename, lineno);

     Fired when a non-root Ruby::Box is created.  `subject` is "".
  */
  probe zjit__invalidate_root_box_only(const char *subject, long count, const char *filename, int lineno);
};

#pragma D attributes Stable/Evolving/Common provider ruby provider
#pragma D attributes Stable/Evolving/Common provider ruby module
#pragma D attributes Stable/Evolving/Common provider ruby function
#pragma D attributes Evolving/Evolving/Common provider ruby name
#pragma D attributes Evolving/Evolving/Common provider ruby args
