# extconf.rb for tcltklib

require 'mkmf'

is_win32 = (/mswin32|mingw|cygwin|bccwin32/ =~ RUBY_PLATFORM)
is_macosx = (/darwin/ =~ RUBY_PLATFORM)

mac_need_framework = 
  is_macosx &&
  enable_config("mac-tcltk-framework", false) &&
  FileTest.directory?("/Library/Frameworks/Tcl.framework/") &&
  FileTest.directory?("/Library/Frameworks/Tk.framework/")

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
**   and Tcl/Tk library on your environment (do coss-compile?). If the 
**   consistency is not kept, some memory troubles (e.g. "Hang-up" or 
**   "Segmentation Fault") may bother you. We strongly you to check the 
**   consistency by your own hand.
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
static Tcl_ThreadDataKey dataKey;
int main() { exit((Tcl_GetThreadData(&dataKey, 1) == dataKey)? 1: 0); }
EOF
      tcl_enable_thread = true
    else
      tcl_enable_thread = false
    end
  end

  # check pthread mode
  if (macro_defined?('HAVE_LIBPTHREAD', '#include "ruby.h"'))
    # ruby -> enable
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
**   than  or equal to Tcl/Tk8.1).
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
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=0'
      return false
    else
      # ruby -> disable && tcl -> disable
      $CPPFLAGS += ' -DWITH_TCL_ENABLE_THREAD=1'
      return true
    end
  end
end

if mac_need_framework || 
   (have_header("tcl.h") && have_header("tk.h") &&
    (is_win32 || find_library("X11", "XOpenDisplay",
      "/usr/X11/lib", "/usr/lib/X11", "/usr/X11R6/lib", "/usr/openwin/lib")) &&
    find_tcl(tcllib, stubs) &&
    find_tk(tklib, stubs))
  $CPPFLAGS += ' -DUSE_TCL_STUBS -DUSE_TK_STUBS' if stubs
  $CPPFLAGS += ' -D_WIN32' if /cygwin/ =~ RUBY_PLATFORM

  if mac_need_framework
    $CPPFLAGS += ' -I/Library/Frameworks/Tcl.framework/headers -I/Library/Frameworks/Tk.framework/Headers'
    $LDFLAGS += ' -framework Tk -framework Tcl'
  end

  create_makefile("tcltklib") if stubs or pthread_check
end
