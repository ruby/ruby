# extconf.rb for tcltklib

have_library("socket", "socket")
have_library("nsl", "gethostbyname")

def search_file(var, include, *path)
  pwd = Dir.getwd
  begin
    for i in path.reverse!
      dir = Dir[i]
      for path in dir
	Dir.chdir path
	files = Dir[include]
	if files.size > 0
	  var << path
	  return files.pop
	end
      end
    end
  ensure
    Dir.chdir pwd
  end
end

$includes = []
search_file($includes, 
	    "tcl.h",
	    "/usr/include/tcl*",
	    "/usr/include",
	    "/usr/local/include/tcl*",
	    "/usr/local/include")
search_file($includes, 
	    "tk.h",
	    "/usr/include/tk*",
	    "/usr/include",
	    "/usr/local/include/tk*",
	    "/usr/local/include")
search_file($includes, 
	    "X11/Xlib.h",
	    "/usr/include",
	    "/usr/X11*/include",
	    "/usr/include",
	    "/usr/X11*/include")

$CFLAGS = "-Wall " + $includes.collect{|path| "-I" + path}.join(" ")

$libraries = []
tcllibfile = search_file($libraries,
			 "libtcl{,7*,8*}.{a,so}",
			 "/usr/lib",
			 "/usr/local/lib")
if tcllibfile
  tcllibfile.sub!(/^lib/, '')
  tcllibfile.sub!(/\.(a|so)$/, '')
end
tklibfile =  search_file($libraries,
			 "libtk{,4*,8*}.{a,so}",
			 "/usr/lib",
			 "/usr/local/lib")
if tklibfile
  tklibfile.sub!(/^lib/, '')
  tklibfile.sub!(/\.(a|so)$/, '')
end
search_file($libraries,
	    "libX11.{a,so}",
	    "/usr/lib",
	    "/usr/X11*/lib")

$LDFLAGS = $libraries.collect{|path| "-L" + path}.join(" ")

have_library("dl", "dlopen")
if have_header("tcl.h") &&
    have_header("tk.h") &&
    have_library("X11", "XOpenDisplay") &&
    have_library("m", "log") &&
    have_library(tcllibfile, "Tcl_FindExecutable") &&
    have_library(tklibfile, "Tk_Init")
  create_makefile("tcltklib")
end
