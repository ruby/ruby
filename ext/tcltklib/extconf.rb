# extconf.rb for tcltklib

require 'mkmf'

is_win32 = (/mswin32|mingw|cygwin|bccwin32/ =~ RUBY_PLATFORM)

unless is_win32
  have_library("nsl", "t_open")
  have_library("socket", "socket")
  have_library("dl", "dlopen")
  have_library("m", "log") 
end

dir_config("tk")
dir_config("tcl")
dir_config("X11")

tklib = with_config("tklib")
tcllib = with_config("tcllib")
stubs = enable_config("tcltk_stubs") || with_config("tcltk_stubs")

def find_tcl(tcllib, stubs)
  paths = ["/usr/local/lib", "/usr/pkg/lib", "/usr/lib"]
  func = stubs ? "Tcl_InitStubs" : "Tcl_FindExecutable"
  if tcllib
    find_library(tcllib, func, *paths)
  elsif find_library("tcl", func, *paths)
    true
  else
    %w[8.5 8.4 8.3 8.2 8.1 8.0 7.6].find { |ver|
      find_library("tcl#{ver}", func, *paths) or
	find_library("tcl#{ver.delete('.')}", func, *paths)
    }
  end
end

def find_tk(tklib, stubs)
  paths = ["/usr/local/lib", "/usr/pkg/lib", "/usr/lib"]
  func = stubs ? "Tk_InitStubs" : "Tk_Init"
  if tklib
    find_library(tklib, func, *paths)
  elsif find_library("tk", func, *paths)
    true
  else
    %w[8.5 8.4 8.3 8.2 8.1 8.0 4.2].find { |ver|
      find_library("tk#{ver}", func, *paths) or
	find_library("tk#{ver.delete('.')}", func, *paths)
    }
  end
end

if have_header("tcl.h") && have_header("tk.h") &&
    (is_win32 || find_library("X11", "XOpenDisplay",
      "/usr/X11/lib", "/usr/lib/X11", "/usr/X11R6/lib", "/usr/openwin/lib")) &&
    find_tcl(tcllib, stubs) &&
    find_tk(tklib, stubs)
  $CPPFLAGS += ' -DUSE_TCL_STUBS -DUSE_TK_STUBS' if stubs
  $CPPFLAGS += ' -D_WIN32' if /cygwin/ =~ RUBY_PLATFORM

  pthread_enabled = macro_defined?('HAVE_LIBPTHREAD', '#include "ruby.h"')

  if try_run(<<EOF)
#include <tcl.h>
static Tcl_ThreadDataKey dataKey;
int main() { exit((Tcl_GetThreadData(&dataKey, 1) == dataKey)? 1: 0); }
EOF
    tcl_enable_thread = true
  else
    tcl_enable_thread = false
  end

  unless pthread_enabled
    if tcl_enable_thread
      # ruby -> disable && tcl -> enable
      puts(%Q'\
*****************************************************************************
**
** PTHREAD SUPPORT MODE ERRROR: 
**
**   Ruby is not compiled with --enable-pthread, but your Tcl/Tk 
**   libararies seems to be compiled with "pthread support". This 
**   combination possibly cause "Hang-up" or "Segmentation Fault" 
**   frequently when Ruby/Tk is working. We NEVER recommend you to 
**   create the library under such combination of pthread support. 
**
**   Please recompile Ruby with "--enable-pthread" configure option 
**   or recompile Tcl/Tk with "--disable-threads" configure option.
**
*****************************************************************************
')
    else
      # ruby -> disable && tcl -> disable
      create_makefile("tcltklib")
    end
  else
    unless tcl_enable_thread
      # ruby -> enable && tcl -> disable
      puts(%Q'\
*****************************************************************************
**
** PTHREAD SUPPORT MODE WARNING: 
**
**   Ruby is compiled with --enable-pthread, but your Tcl/Tk libraries
**   seems to be compiled without "pthread support". Although You can 
**   create tcltklib library, this combination may cause memory trouble 
**   (e.g. "Hang-up" or "Segmentation Fault"). If you have no reason you
**   must have to keep current pthread support status, we recommend you 
**   to make both or neither libraries to support pthread.
**
**   If you want change the status of pthread support, please recompile 
**   Ruby without "--enable-pthread" configure option or recompile Tcl/Tk 
**   with "--enable-threads" configure option (if your Tcl/Tk is later 
**   than Tcl/Tk8.1).
**
*****************************************************************************
')
    end
    # ruby -> enable && tcl -> enable/disable

    create_makefile("tcltklib")
  end
end
