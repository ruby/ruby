# extconf.rb for tcltklib

require 'mkmf'

have_library("nsl", "t_open")
have_library("socket", "socket")
have_library("dl", "dlopen")
have_library("m", "log") 

dir_config("tk")
dir_config("tcl")
dir_config("X11")

tklib = with_config("tklib")
tcllib = with_config("tcllib")

def find_tcl(tcllib)
  paths = ["/usr/local/lib", "/usr/pkg"]
  func = "Tcl_FindExecutable"
  if tcllib
    find_library(tcllib, func, *paths)
  else
    find_library("tcl", func, *paths) or
      find_library("tcl8.0", func, *paths) or
      find_library("tcl7.6", func, *paths)
  end
end

def find_tk(tklib)
  paths = ["/usr/local/lib", "/usr/pkg"]
  func = "Tk_Init"
  if tklib
    find_library(tklib, func, *paths)
  else
    find_library("tk", func, *paths) or
      find_library("tk8.0", func, *paths) or
      find_library("tk4.2", func, *paths)
  end
end

if have_header("tcl.h") && have_header("tk.h") &&
    (/mswin32/ =~ RUBY_PLATFORM || find_library("X11", "XOpenDisplay",
	"/usr/X11/lib", "/usr/X11R6/lib", "/usr/openwin/lib")) &&
    find_tcl(tcllib) &&
    find_tk(tklib)
  create_makefile("tcltklib")
end
