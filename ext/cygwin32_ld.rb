#!/usr/local/bin/ruby
require '../../rbconfig'
include Config

args = ARGV.join(" ")

objs = []
flags = []
libname = ''
Init = "../init"

path = ''

def writeInit
  out = open("#{Init}.c", "w")

  out.print %q@
#include <windows.h>
#include <stdio.h>

extern struct _reent *__imp_reent_data;
WINAPI dll_entry(int a, int b, int c)
{
    _impure_ptr =__imp_reent_data;
    return 1;
}
main(){}
//void impure_setup(struct _reent *_impure_ptrMain)
//{
//    _impure_ptr =__imp_reent_data;
//}
@
  out.close
end

def xsystem cmd
  print cmd, "\n"
  system cmd
end

if args =~ /-o (\w+)\.dll/i
  libname = $1
  # Check for path:
  if libname =~ /(\w+\/)(\w+)$/
    path = $1
    libname = $2
  end
  for arg in ARGV
    case arg
    when /\.[oa]$/i
      objs.push(arg)
    when /-o/, /\w+\.dll/i
      ;
    else
      flags << arg
    end
  end

  writeInit unless FileTest.exist?("#{Init}.c")
  unless FileTest.exist?("#{Init}.o") and
    File.mtime("#{Init}.c") < File.mtime("#{Init}.o")
    xsystem "gcc -c #{Init}.c -o #{Init}.o"
  end
  
  command = "echo EXPORTS > #{libname}.def"
  xsystem command
#  xsystem "echo impure_setup >> #{libname}.def"
  xsystem "nm --extern-only " + objs.join(" ") +
    "  | sed -n '/^........ [CDT] _/s///p' >> #{libname}.def"

  command = "gcc -nostdlib -o junk.o -Wl,--base-file,#{libname}.base,--dll " +
    objs.join(" ") + "  #{Init}.o "
  command.concat(flags.join(" ") +
    " -Wl,-e,_dll_entry@12 -lcygwin -lkernel32 #{CONFIG['srcdir']}/libruby.a")
  xsystem command

  command = "dlltool --as=as --dllname #{libname}.dll --def #{libname}.def --base-file #{libname}.base --output-exp #{libname}.exp"
  xsystem command
  
  command = "gcc -s -nostdlib -o #{libname}.dll -Wl,--dll #{libname}.exp " +
    objs.join(" ") + "  #{Init}.o "
  command.concat(flags.join(" ") +
    " -Wl,-e,_dll_entry@12 -lcygwin -lkernel32 #{CONFIG['srcdir']}/libruby.a")
  xsystem command
  File.unlink "junk.o" if FileTest.exist? "junk.o"

else
  # no special processing, just call ld
  xsystem "ld #{args}"
end
