# extconf.rb for tcltklib

require 'mkmf'

if RUBY_PLATFORM !~ /mswin32|mingw|cygwin/
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
  elsif RUBY_PLATFORM =~ /mswin32|mingw|cygwin/
    find_library("tcl", func, *paths) or
      find_library("tcl84", func, *paths) or
      find_library("tcl83", func, *paths) or
      find_library("tcl82", func, *paths) or
      find_library("tcl80", func, *paths) or
      find_library("tcl76", func, *paths)
  else
    find_library("tcl", func, *paths) or
      find_library("tcl8.4", func, *paths) or
      find_library("tcl8.3", func, *paths) or
      find_library("tcl8.2", func, *paths) or
      find_library("tcl8.0", func, *paths) or
      find_library("tcl7.6", func, *paths)
  end
end

def find_tk(tklib, stubs)
  paths = ["/usr/local/lib", "/usr/pkg/lib", "/usr/lib"]
  func = stubs ? "Tk_InitStubs" : "Tk_Init"
  if tklib
    find_library(tklib, func, *paths)
  elsif RUBY_PLATFORM =~ /mswin32|mingw|cygwin/
    find_library("tk", func, *paths) or
      find_library("tk84", func, *paths) or
      find_library("tk83", func, *paths) or
      find_library("tk82", func, *paths) or
      find_library("tk80", func, *paths) or
      find_library("tk42", func, *paths)
  else
    find_library("tk", func, *paths) or
      find_library("tk8.4", func, *paths) or
      find_library("tk8.3", func, *paths) or
      find_library("tk8.2", func, *paths) or
      find_library("tk8.0", func, *paths) or
      find_library("tk4.2", func, *paths)
  end
end

if have_header("tcl.h") && have_header("tk.h") &&
    (/mswin32|mingw|cygwin/ =~ RUBY_PLATFORM || find_library("X11", "XOpenDisplay",
	"/usr/X11/lib", "/usr/X11R6/lib", "/usr/openwin/lib")) &&
    find_tcl(tcllib, stubs) &&
    find_tk(tklib, stubs)
  $CPPFLAGS += ' -DUSE_TCL_STUBS -DUSE_TK_STUBS' if stubs
  $CPPFLAGS += ' -D_WIN32' if /cygwin/ =~ RUBY_PLATFORM
  create_makefile("tcltklib")
end
