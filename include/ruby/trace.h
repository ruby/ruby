/**********************************************************************

  trace.h -

  $Author$

  Copyright (C) 2009 Yuki Sonoda (Yugui)

**********************************************************************/

#ifndef RUBY_TRACE_H
#define RUBY_TRACE_H

#define RUBY_TRACING_MODEL_NONE 0
#define RUBY_TRACING_MODEL_DTRACE 1

#if RUBY_TRACING_MODEL == RUBY_TRACING_MODEL_NONE
# define TRACE_METHOD_ENTRY_ENABLED() 0
# define TRACE_METHOD_RETURN_ENABLED() 0
# define TRACE_RAISE_ENABLED() 0
# define TRACE_RESCUE_ENABLED() 0
# define TRACE_LINE_ENABLED() 0
# define TRACE_GC_BEGIN_ENABLED() 0
# define TRACE_GC_END_ENABLED() 0
# define TRACE_THREAD_INIT_ENABLED()  0
# define TRACE_THREAD_TERM_ENABLED()  0
# define TRACE_THREAD_LEAVE_ENABLED() 0
# define TRACE_THREAD_ENTER_ENABLED() 0
# define TRACE_OBJECT_CREATE_ENABLED() 0
# define TRACE_OBJECT_FREE_ENABLED() 0
# define TRACE_INSN_ENTRY_ENABLED() 0
# define TRACE_INSN_RETURN_ENABLED() 0
# define TRACE_RUBY_PROBE_ENABLED() 0

# define FIRE_METHOD_ENTRY(receiver, classname, methodname, sourcefile, sourceline) ((void)0)
# define FIRE_METHOD_RETURN(receiver, classname, methodname, sourcefile, sourceline) ((void)0)
# define FIRE_RAISE(exception, classname, sourcename, sourceline) ((void)0)
# define FIRE_RESCUE(exception, classname, sourcename, sourceline) ((void)0)
# define FIRE_LINE(sourcename, sourceline) ((void)0)
# define FIRE_GC_BEGIN() ((void)0)
# define FIRE_GC_END() ((void)0)
# define FIRE_THREAD_INIT(th, sourcefile, sourceline) ((void)0)
# define FIRE_THREAD_TERM(th, sourcefile, sourceline) ((void)0)
# define FIRE_THREAD_LEAVE(th, sourcefile, sourceline) ((void)0)
# define FIRE_THREAD_ENTER(th, sourcefile, sourceline) ((void)0)
# define FIRE_OBJECT_CREATE(obj, classname, sourcefile, sourceline) ((void)0)
# define FIRE_OBJECT_FREE(obj) ((void)0)
# define FIRE_INSN_ENTRY(insnname, operands, sourcename, sourceline) ((void)0)
# define FIRE_INSN_RETURN(insnname, operands, sourcename, sourceline) ((void)0)
# define FIRE_RUBY_PROBE(name, data) ((void)0)

#elif RUBY_TRACING_MODEL == RUBY_TRACING_MODEL_DTRACE
# include "ruby/trace_dtrace.h"
# define TRACE_METHOD_ENTRY_ENABLED()  RUBY_METHOD_ENTRY_ENABLED()
# define TRACE_METHOD_RETURN_ENABLED() RUBY_METHOD_RETURN_ENABLED()
# define TRACE_RAISE_ENABLED()         RUBY_RAISE_ENABLED()
# define TRACE_RESCUE_ENABLED()        RUBY_RESCUE_ENABLED()
# define TRACE_LINE_ENABLED()          RUBY_LINE_ENABLED()
# define TRACE_GC_BEGIN_ENABLED()      RUBY_GC_BEGIN_ENABLED()
# define TRACE_GC_END_ENABLED()        RUBY_GC_END_ENABLED()
# define TRACE_THREAD_INIT_ENABLED()  RUBY_THREAD_INIT_ENABLED()
# define TRACE_THREAD_TERM_ENABLED()  RUBY_THREAD_TERM_ENABLED()
# define TRACE_THREAD_LEAVE_ENABLED()  RUBY_THREAD_LEAVE_ENABLED()
# define TRACE_THREAD_ENTER_ENABLED()  RUBY_THREAD_ENTER_ENABLED()
# define TRACE_OBJECT_CREATE_ENABLED() RUBY_OBJECT_CREATE_ENABLED()
# define TRACE_OBJECT_FREE_ENABLED()   RUBY_OBJECT_FREE_ENABLED()
# define TRACE_INSN_ENTRY_ENABLED()    RUBY_INSN_ENTRY_ENABLED()
# define TRACE_INSN_RETURN_ENABLED()   RUBY_INSN_RETURN_ENABLED()
# define TRACE_RUBY_PROBE_ENABLED()    RUBY_RUBY_PROBE_ENABLED()

# define FIRE_METHOD_ENTRY(receiver, classname, methodname, sourcefile, sourceline) \
   RUBY_METHOD_ENTRY(receiver, classname, methodname, sourcefile, sourceline)
# define FIRE_METHOD_RETURN(receiver, classname, methodname, sourcefile, sourceline) \
   RUBY_METHOD_RETURN(receiver, classname, methodname, sourcefile, sourceline)
# define FIRE_RAISE(exception, classname, sourcename, sourceline) \
   RUBY_RAISE(exception, classname, sourcename, sourceline)
# define FIRE_RESCUE(exception, classname, sourcename, sourceline) \
   RUBY_RESCUE(exception, classname, sourcename, sourceline)
# define FIRE_LINE(sourcename, sourceline) \
   RUBY_LINE(sourcename, sourceline)
# define FIRE_GC_BEGIN()     RUBY_GC_BEGIN()
# define FIRE_GC_END()       RUBY_GC_END()
# define FIRE_THREAD_INIT(th, sourcefile, sourceline) \
   RUBY_THREAD_INIT(th, (char*)sourcefile, sourceline)
# define FIRE_THREAD_TERM(th, sourcefile, sourceline) \
   RUBY_THREAD_TERM(th, (char*)sourcefile, sourceline)
# define FIRE_THREAD_LEAVE(th, sourcefile, sourceline) \
   RUBY_THREAD_LEAVE(th, (char*)sourcefile, sourceline)
# define FIRE_THREAD_ENTER(th, sourcefile, sourceline) \
   RUBY_THREAD_ENTER(th, (char*)sourcefile, sourceline)
# define FIRE_OBJECT_CREATE(obj, classname, sourcefile, sourceline) \
   RUBY_OBJECT_CREATE(obj, (char*)classname, (char*)sourcefile, sourceline)
# define FIRE_OBJECT_FREE(obj) \
   RUBY_OBJECT_FREE(obj)
# define FIRE_INSN_ENTRY(insnname, operands, sourcename, sourceline) \
   RUBY_INSN_ENTRY(insnname, operands, sourcename, sourceline)
# define FIRE_INSN_RETURN(insnname, operands, sourcename, sourceline) \
   RUBY_INSN_RETURN(insnname, operands, sourcename, sourceline)
# define FIRE_RUBY_PROBE(name, data) \
   RUBY_RUBY_PROBE(name, data)
#endif

#define FIRE_RAISE_FATAL() FIRE_RAISE(0, (char*)"fatal", (char*)"<unknown>", 0)

#endif
