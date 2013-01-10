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
  probe method__entry(const char *, const char *, const char *, int);
  /*
     ruby:::method-return(classname, methodname, filename, lineno);

     This probe is fired just after a method has returned. The arguments are
     the same as "ruby:::function-entry".
  */
  probe method__return(const char *, const char *, const char *, int);

  /*
     ruby:::cmethod-entry(classname, methodname, filename, lineno);

     This probe is fired just before a C method is entered. The arguments are
     the same as "ruby:::function-entry".
  */
  probe cmethod__entry(const char *, const char *, const char *, int);
  /*
     ruby:::cmethod-return(classname, methodname, filename, lineno);

     This probe is fired just before a C method returns. The arguments are
     the same as "ruby:::function-entry".
  */
  probe cmethod__return(const char *, const char *, const char *, int);

  /*
     ruby:::require-entry(requiredfile, filename, lineno);

     This probe is fired on calls to `rb_require_safe` (when a file is
     required).

     * `requiredfile` is the name of the file to be required (string).
     * `filename` is the file that called "require" (string).
     * `lineno` is the line number where the call to require was made (int).
  */
  probe require__entry(const char *, const char *, int);

  /*
     ruby:::require-return(requiredfile, filename, lineno);

     This probe is fired just before `rb_require_safe` (when a file is required)
     returns.  The arguments are the same as "ruby:::require-entry".  This
     probe will not fire if there was an exception during file require.
  */
  probe require__return(const char *, const char *, int);

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
  probe find__require__entry(const char *, const char *, int);

  /*
     ruby:::find-require-return(requiredfile, filename, lineno);

     This probe is fired right after `search_required` returns.  See the
     documentation for "ruby:::find-require-entry" for more details.  Arguments
     for this probe are the same as "ruby:::find-require-entry".
  */
  probe find__require__return(const char *, const char *, int);

  /*
     ruby:::load-entry(loadedfile, filename, lineno);

     This probe is fired when calls to "load" are made.  The arguments are the
     same as "ruby:::require-entry".
  */
  probe load__entry(const char *, const char *, int);

  /*
     ruby:::load-return(loadedfile, filename, lineno);

     This probe is fired when "load" returns.  The arguments are the same as
     "ruby:::load-entry".
  */
  probe load__return(const char *, const char *, int);

  /*
     ruby:::raise(classname, filename, lineno);

     This probe is fired when an exception is raised.

     * `classname` is the class name of the raised exception (string)
     * `filename` the name of the file where the exception was raised (string)
     * `lineno` the line number in the file where the exception was raised (int)
  */
  probe raise(const char *, const char *, int);

  /*
     ruby:::object-create(classname, filename, lineno);

     This probe is fired when an object is about to be allocated.

      * `classname` the class of the allocated object (string)
      * `filename` the name of the file where the object is allocated (string)
      * `lineno` the line number in the file where the object is allocated (int)
  */
  probe object__create(const char *, const char *, int);

  /*
     ruby:::array-create(length, filename, lineno);

     This probe is fired when an Array is about to be allocated.

      * `length` the size of the array (long)
      * `filename` the name of the file where the array is allocated (string)
      * `lineno` the line number in the file where the array is allocated (int)
  */
  probe array__create(long, const char *, int);

  /*
     ruby:::hash-create(length, filename, lineno);

     This probe is fired when a Hash is about to be allocated.

      * `length` the size of the hash (long)
      * `filename` the name of the file where the hash is allocated (string)
      * `lineno` the line number in the file where the hash is allocated (int)
  */
  probe hash__create(long, const char *, int);

  /*
     ruby:::string-create(length, filename, lineno);

     This probe is fired when a String is about to be allocated.

      * `length` the size of the string (long)
      * `filename` the name of the file where the string is allocated (string)
      * `lineno` the line number in the file where the string is allocated (int)
  */
  probe string__create(long, const char *, int);

  /*
     ruby:::parse-begin(sourcefile, lineno);

     Fired just before parsing and compiling a source file.

     * `sourcefile` the file being parsed (string)
     * `lineno` the line number where the source starts (int)
  */
  probe parse__begin(const char *, int);

  /*
     ruby:::parse-end(sourcefile, lineno);

     Fired just after parsing and compiling a source file.

     * `sourcefile` the file being parsed (string)
     * `lineno` the line number where the source ended (int)
  */
  probe parse__end(const char *, int);

#if VM_COLLECT_USAGE_DETAILS
  probe insn(const char *);
  probe insn__operand(const char *, const char *);
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
};

#pragma D attributes Stable/Evolving/Common provider ruby provider
#pragma D attributes Stable/Evolving/Common provider ruby module
#pragma D attributes Stable/Evolving/Common provider ruby function
#pragma D attributes Evolving/Evolving/Common provider ruby name
#pragma D attributes Evolving/Evolving/Common provider ruby args
