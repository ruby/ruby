require 'mkmf'

begin # for the exception SystemExit

$:.unshift File.dirname(__FILE__)
require 'type'

if( ARGV.include?("--help") )
  print <<EOF
  --help             print this messages
  --with-type-char   strictly use type 'char'
  --with-type-short  strictly use type 'short'
  --with-type-float  strictly use type 'float'
  --with-args=<max_arg>
  --with-callback=<max_callback>
  --enable-asm       use the embedded assembler for passing arguments.
                     (this option is available for i386 machine now.)
  --enable-dlstack   use a stack emulation for constructing function call.
EOF
  exit(0)
end

($CPPFLAGS || $CFLAGS) << " -I."

if (Config::CONFIG['CC'] =~ /gcc/)  # from Win32API
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

$with_dlstack ||= true
$with_asm = ! $with_dlstack

$with_type_int = try_cpp(<<EOF)
#include "config.h"
#if SIZEOF_INT == SIZEOF_LONG
#error int not needed
#endif
EOF

$with_type_float = try_cpp(<<EOF)
#include "config.h"
#if SIZEOF_FLOAT == SIZEOF_DOUBLE
#error float not needed
#endif
EOF

$with_type_voidp = try_cpp(<<EOF)
#include "config.h"
#if SIZEOF_VOIDP == SIZEOF_INT || SIZEOF_VOIDP == SIZEOF_LONG
#error void* not needed
#endif
EOF

$with_type_char  = DLTYPE[CHAR][:sym]
$with_type_short = DLTYPE[SHORT][:sym]
$with_type_long  = DLTYPE[LONG][:sym]
$with_type_double= DLTYPE[DOUBLE][:sym]
$with_type_int   &= DLTYPE[INT][:sym]
$with_type_float &= DLTYPE[FLOAT][:sym]
$with_type_voidp &= DLTYPE[VOIDP][:sym]

$with_type_char  = enable_config("type-char", $with_type_char)
$with_type_short = enable_config("type-short", $with_type_short)
$with_type_float = enable_config("type-float", $with_type_float)

$with_asm        = enable_config("asm", $with_asm)
$with_dlstack    = enable_config("dlstack", $with_dlstack)

args = with_config("args")
max_arg = nil
if( $with_asm || $with_dlstack )
  $with_type_char = true
  $with_type_short = true
  $with_type_float = true
  max_arg = 0
end
if( args )
  max_arg = args.to_i
  if( !max_arg )
    print("--with-args=<max_arg>\n")
    exit(1)
  end
end
max_arg   ||= 6

max_callback = with_config("callback","10").to_i
callback_types = DLTYPE.keys.length


$dlconfig_h = <<EOF
#define MAX_ARG           #{max_arg}
EOF

def dlc_define(const)
  $dlconfig_h << "#if !defined(#{const})\n" +
                 "# define #{const}\n" +
                 "#endif\n"
end

$dlconfig_h << "#define MAX_CALLBACK #{max_callback}\n"
$dlconfig_h << "#define CALLBACK_TYPES #{callback_types}\n"
if( $with_dlstack )
  $dlconfig_h << "#define USE_DLSTACK\n"
else
  if( $with_asm )
    $dlconfig_h << "#define USE_INLINE_ASM\n"
  end
end
if( $with_type_char )
  $dlconfig_h << "#define WITH_TYPE_CHAR\n"
end
if( $with_type_short )
  $dlconfig_h << "#define WITH_TYPE_SHORT\n"
end
if( $with_type_long )
  $dlconfig_h << "#define WITH_TYPE_LONG\n"
end
if( $with_type_double )
  $dlconfig_h << "#define WITH_TYPE_DOUBLE\n"
end
if( $with_type_float )
  $dlconfig_h << "#define WITH_TYPE_FLOAT\n"
end
if( $with_type_int )
  $dlconfig_h << "#define WITH_TYPE_INT\n"
end
if( $with_type_voidp )
  $dlconfig_h << "#define WITH_TYPE_VOIDP\n"
end

if( have_header("windows.h") )
  have_library("kernel32")
  have_func("GetLastError", "windows.h")
  dlc_define("HAVE_WINDOWS_H")
  have_windows_h = true
end

if( have_header("dlfcn.h") )
  dlc_define("HAVE_DLFCN_H")
  have_library("dl")
  have_func("dlopen")
  have_func("dlclose")
  have_func("dlsym")
  if( have_func("dlerror") )
    dlc_define("HAVE_DLERROR")
  end
elsif ( have_windows_h )
  have_func("LoadLibrary")
  have_func("FreeLibrary")
  have_func("GetProcAddress")
else
  exit(0)
end

def File.update(file, str)
  begin
    open(file){|f|f.read} == str
  rescue Errno::ENOENT
    false
  end or open(file, "w"){|f|f.print(str)}
end

File.update("dlconfig.h", <<EOF)
#ifndef DLCONFIG_H
#define DLCONFIG_H
#{$dlconfig_h}
#endif /* DLCONFIG_H */
EOF

File.update("dlconfig.rb", <<EOF)
MAX_ARG = #{max_arg}
MAX_CALLBACK = #{max_callback}
CALLBACK_TYPES = #{callback_types}
DLTYPE[CHAR][:sym]  = #{$with_type_char}
DLTYPE[SHORT][:sym] = #{$with_type_short}
DLTYPE[INT][:sym]   = #{$with_type_int}
DLTYPE[LONG][:sym]  = #{$with_type_long}
DLTYPE[FLOAT][:sym] = #{$with_type_float}
DLTYPE[DOUBLE][:sym]= #{$with_type_double}
DLTYPE[VOIDP][:sym] = #{$with_type_voidp}
EOF

$INSTALLFILES = [
  ["./dlconfig.h", "$(archdir)$(target_prefix)", "."],
  ["dl.h", "$(archdir)$(target_prefix)", ""],
]
$cleanfiles = %w[test/test.o]
$distcleanfiles = %w[call.func callback.func cbtable.func dlconfig.rb
./dlconfig.h test/libtest.so test/*~ *~ mkmf.log]

create_makefile('dl')
rescue SystemExit
  # do nothing
end
