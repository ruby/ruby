# extconf.rb for tcltklib

require 'mkmf'

is_win32 = (/mswin32|mingw|cygwin|bccwin32/ =~ RUBY_PLATFORM)
#is_macosx = (/darwin/ =~ RUBY_PLATFORM)

def find_framework(tcl_hdr, tk_hdr)
  if framework_dir = with_config("tcltk-framework")
    paths = [framework_dir]
  else
    unless tcl_hdr || tk_hdr ||
        enable_config("tcltk-framework", false) ||
        enable_config("mac-tcltk-framework", false)
      return false
    end
    paths = ["/Library/Frameworks", "/System/Library/Frameworks"]
  end

  checking_for('Tcl/Tk Framework') {
    paths.find{|dir|
      dir.strip!
      dir.chomp!('/')
      (tcl_hdr || FileTest.directory?(dir + "/Tcl.framework/") ) &&
        (tk_hdr || FileTest.directory?(dir + "/Tk.framework/") )
    }
  }
end

tcl_framework_header = with_config("tcl-framework-header")
tk_framework_header  = with_config("tk-framework-header")

tcltk_framework = find_framework(tcl_framework_header, tk_framework_header)

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

use_X = with_config("X11", (! is_win32))

def find_tcl(tcllib, stubs)
  paths = ["/usr/local/lib64", "/usr/local/lib", "/usr/pkg/lib64", "/usr/pkg/lib", "/usr/lib64", "/usr/lib"]
  if stubs
    func = "Tcl_InitStubs"
    lib = "tclstub"
  else
    func = "Tcl_FindExecutable"
    lib = "tcl"
  end
  if tcllib
    find_library(tcllib, func, *paths)
  elsif find_library(lib, func, *paths)
    true
  else
    %w[8.5 8.4 8.3 8.2 8.1 8.0 7.6].find { |ver|
      find_library("#{lib}#{ver}", func, *paths) or
        find_library("#{lib}#{ver.delete('.')}", func, *paths) or
        find_library("tcl#{ver}", func, *paths) or
        find_library("tcl#{ver.delete('.')}", func, *paths)
    }
  end
end

def find_tk(tklib, stubs)
  paths = ["/usr/local/lib", "/usr/pkg/lib", "/usr/lib"]
  if stubs
    func = "Tk_InitStubs"
    lib = "tkstub"
  else
    func = "Tk_Init"
    lib = "tk"
  end
  if tklib
    find_library(tklib, func, *paths)
  elsif find_library(lib, func, *paths)
    true
  else
    %w[8.5 8.4 8.3 8.2 8.1 8.0 4.2].find { |ver|
      find_library("#{lib}#{ver}", func, *paths) or
        find_library("#{lib}#{ver.delete('.')}", func, *paths) or
        find_library("tk#{ver}", func, *paths) or
        find_library("tk#{ver.delete('.')}", func, *paths)
    }
  end
end

def pthread_check()
  tcl_major_ver = nil
  tcl_minor_ver = nil

  # Is tcl-thread given by user ?
  case enable_config("tcl-thread")
  when true
    tcl_enable_thread = true
  when false
    tcl_enable_thread = false
  else
    tcl_enable_thread = nil
  end

  if (tclConfig = with_config("tclConfig-file"))
    if tcl_enable_thread == true
      puts("Warning: --with-tclConfig-file option is ignored, because --enable-tcl-thread option is given.")
    elsif tcl_enable_thread == false
      puts("Warning: --with-tclConfig-file option is ignored, because --disable-tcl-thread option is given.")
    else
      # tcl-thread is unknown and tclConfig.sh is given
      begin
        open(tclConfig, "r") do |cfg|
          while line = cfg.gets()
            if line =~ /^\s*TCL_THREADS=(0|1)/
              tcl_enable_thread = ($1 == "1")
              break
            end

            if line =~ /^\s*TCL_MAJOR_VERSION=("|')(\d+)\1/
              tcl_major_ver = $2
              if tcl_major_ver =~ /^[1-7]$/
                tcl_enable_thread = false
                break
              end
              if tcl_major_ver == "8" && tcl_minor_ver == "0"
                tcl_enable_thread = false
                break
              end
            end

            if line =~ /^\s*TCL_MINOR_VERSION=("|')(\d+)\1/
              tcl_minor_ver = $2
              if tcl_major_ver == "8" && tcl_minor_ver == "0"
                tcl_enable_thread = false
                break
              end
            end
          end
        end

        if tcl_enable_thread == nil
          # not find definition
          if tcl_major_ver
            puts("Warning: '#{tclConfig}' doesn't include TCL_THREADS definition.")
          else
            puts("Warning: '#{tclConfig}' may not be a tclConfig file.")
          end
          tclConfig = false
        end
      rescue Exception
        puts("Warning: fail to read '#{tclConfig}'!! --> ignore the file")
        tclConfig = false
      end
    end
  end

  if tcl_enable_thread == nil && !tclConfig
    # tcl-thread is unknown and tclConfig is unavailable
    begin
      try_run_available = try_run("int main() { exit(0); }")
    rescue Exception
      # cannot try_run. Is CROSS-COMPILE environment?
      puts(%Q'\
*****************************************************************************
**
** PTHREAD SUPPORT CHECK WARNING: 
**
**   We cannot check the consistency of pthread support between Ruby 
**   and the Tcl/Tk library in your environment (are you perhaps
**   cross-compiling?). If pthread support for these 2 packages is
**   inconsistent you may find you get errors when running Ruby/Tk
**   (e.g. hangs or segmentation faults).  We strongly recommend
**   you to check the consistency manually.
**
*****************************************************************************
')
      return true
    end
  end

  if tcl_enable_thread == nil
    # tcl-thread is unknown
    if try_run(<<EOF)
#include <tcl.h>
int main() { 
   Tcl_Interp *ip;
   ip = Tcl_CreateInterp();
   exit((Tcl_Eval(ip, "set tcl_platform(threaded)") == TCL_OK)? 0: 1);
}
EOF
      tcl_enable_thread = true
    elsif try_run(<<EOF)
#include <tcl.h>
static Tcl_ThreadDataKey dataKey;
int main() { exit((Tcl_GetThreadData(&dataKey, 1) == dataKey)? 1: 0); }
EOF
      tcl_enable_thread = true
    else
      tcl_enable_thread = false
    end
  end

  # check pthread mode
  if (macro_defined?('HAVE_NATIVETHREAD', '#include "ruby.h"'))
    # ruby -> enable
    unless tcl_enable_thread
      # ruby -> enable && tcl -> disable
      puts(%Q'\
*****************************************************************************
**
** PTHREAD SUPPORT MODE WARNING: 
**
**   Ruby is compiled with --enable-pthread, but your Tcl/Tk library
**   seems to be compiled without pthread support. Although you can
**   create the tcltklib library, this combination may cause errors
**   (e.g. hangs or segmentation faults). If you have no reason to
**   keep the current pthread support status, we recommend you reconfigure
**   and recompile the libraries so that both or neither support pthreads.
**
**   If you want change the status of pthread support, please recompile 
**   Ruby without "--enable-pthread" configure option or recompile Tcl/Tk 
**   with "--enable-threads" configure option (if your Tcl/Tk is later 
**   than or equal to Tcl/Tk 8.1).
**
*****************************************************************************
')
    end

    # ruby -> enable && tcl -> enable/disable
    if tcl_enable_thread
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=1'
    else
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=0'
    end

    return true

  else
    # ruby -> disable
    if tcl_enable_thread
      # ruby -> disable && tcl -> enable
      puts(%Q'\
*****************************************************************************
**
** PTHREAD SUPPORT MODE ERROR: 
**
**   Ruby is not compiled with --enable-pthread, but your Tcl/Tk 
**   library seems to be compiled with pthread support. This
**   combination may cause frequent hang or segmentation fault
**   errors when Ruby/Tk is working. We recommend that you NEVER
**   create the library with such a combination of pthread support.
**
**   Please recompile Ruby with the "--enable-pthread" configure option
**   or recompile Tcl/Tk with the "--disable-threads" configure option.
**
*****************************************************************************
')
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=1'
      return false
    else
      # ruby -> disable && tcl -> disable
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=0'
      return true
    end
  end
end

if tcltk_framework || 
   (have_header("tcl.h") && have_header("tk.h") &&
      ( !use_X || find_library("X11", "XOpenDisplay",
                               "/usr/X11/lib64",     "/usr/X11/lib",
                               "/usr/lib64/X11",     "/usr/lib/X11",
                               "/usr/X11R6/lib64",   "/usr/X11R6/lib",
                               "/usr/openwin/lib64", "/usr/openwin/lib")) &&
    find_tcl(tcllib, stubs) &&
    find_tk(tklib, stubs))
  $CPPFLAGS += ' -DUSE_TCL_STUBS -DUSE_TK_STUBS' if stubs
  $CPPFLAGS += ' -D_WIN32' if /cygwin/ =~ RUBY_PLATFORM

  if tcltk_framework
    if tcl_framework_header
      $CPPFLAGS += " -I#{tcl_framework_header}"
    else
      $CPPFLAGS += " -I#{tcltk_framework}/Tcl.framework/Headers"
    end

    if tk_framework_header
      $CPPFLAGS += " -I#{tk_framework_header}"
    else
      $CPPFLAGS += " -I#{tcltk_framework}/Tk.framework/Headers"
    end

    $LDFLAGS += ' -framework Tk -framework Tcl'
  end

  if stubs or pthread_check
    # create Makefile

    # for SUPPORT_STATUS
    $INSTALLFILES ||= []
    $INSTALLFILES << ["lib/tkextlib/SUPPORT_STATUS", "$(RUBYLIBDIR)", "lib"]

    # create
    create_makefile("tcltklib")
  end
end
