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
  --with-asm         use the embedded assembler for passing arguments.
                     (this option is available for i386 machine now.)
  --with-dlstack     use a stack emulation for constructing function call. [experimental]
  --with-args=<max_arg>,<max_cbarg>,<max_cbent>
                     <max_arg>:   maximum number of arguments of the function
                     <max_cbarg>: maximum number of arguments of the callback
                     <max_cbent>: maximum number of callback entries
EOF
  exit(0)
end

($CPPFLAGS || $CFLAGS) << " -I."

if (Config::CONFIG['CC'] =~ /gcc/)  # from Win32API
  $CFLAGS << " -fno-defer-pop -fno-omit-frame-pointer"
end

if (Config::CONFIG['CC'] =~ /gcc/) && (Config::CONFIG['arch'] =~ /i.86/)
  $with_asm = true
else
  $with_asm = false
end
$with_dlstack = false

$with_type_int = try_run(<<EOF)
int main(){ return sizeof(int) == sizeof(long); }
EOF

$with_type_float = try_run(<<EOF)
int main(){ return sizeof(float) == sizeof(double); }
EOF

$with_type_voidp = try_run(<<EOF)
int main(){
  return (sizeof(void *) == sizeof(long))
         || (sizeof(void *) == sizeof(int));
}
EOF

$with_type_char  = DLTYPE[CHAR][:sym]
$with_type_short = DLTYPE[SHORT][:sym]
$with_type_long  = DLTYPE[LONG][:sym]
$with_type_double= DLTYPE[DOUBLE][:sym]
$with_type_int   &= DLTYPE[INT][:sym]
$with_type_float &= DLTYPE[FLOAT][:sym]
$with_type_voidp &= DLTYPE[VOIDP][:sym]

$with_cbtype_voidp = DLTYPE[VOIDP][:cb]

$with_type_char  = enable_config("type-char", $with_type_char)
$with_type_short = enable_config("type-short", $with_type_short)
$with_type_float = enable_config("type-float", $with_type_float)

$with_asm        = enable_config("asm", $with_asm)
$with_dlstack    = enable_config("dlstack", $with_dlstack)

args = with_config("args")
max_arg = max_cbarg = max_cbent = nil
if( $with_asm || $with_dlstack )
  $with_type_char = true
  $with_type_short = true
  $with_type_float = true
  max_arg = 0
end
if( args )
  max_arg,max_cbarg,max_cbent = args.split(",").collect{|c| c.to_i}
  if( !(max_arg && max_cbarg && max_cbent) )
    print("--with-args=<max_arg>,<max_cbarg>,<max_cbent>\n")
    exit(1)
  end
end
max_arg   ||= 6
max_cbarg ||= 3
max_cbent ||= 3

max_callback_type = types2num(DLTYPE.keys.sort[-1,1] * (max_cbarg + 1)) + 1
max_callback      = max_cbent

#m = [1].pack("i")
#c,cs = m.unpack("c")
#bigendian = (c == 0)
#print("bigendian ... #{bigendian ? 'true' : 'false'}\n")


$dlconfig_h = <<EOF
#define MAX_ARG   #{max_arg}
#define MAX_CBARG #{max_cbarg}
#define MAX_CBENT #{max_cbent}
#define MAX_CALLBACK_TYPE #{max_callback_type}
#define MAX_CALLBACK      #{max_callback}
EOF

def dlc_define(const)
  $dlconfig_h << "#if !defined(#{const})\n" +
                 "# define #{const}\n" +
                 "#endif\n"
end

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
if( $with_cbtype_voidp )
  $dlconfig_h << "#define WITH_CBTYPE_VOIDP\n"
end
#if( bigendian )
#  $dlconfig_h << "#define BIGENDIAN"
#else
#  $dlconfig_h << "#define LITTLEENDIAN"
#end


if( have_header("dlfcn.h") )
  dlc_define("HAVE_DLFCN_H")
  have_library("dl")
  have_func("dlopen")
  have_func("dlclose")
  have_func("dlsym")
  if( have_func("dlerror") )
    dlc_define("HAVE_DLERROR")
  end
elsif( have_header("windows.h") )
  dlc_define("HAVE_WINDOWS_H")
  have_func("LoadLibrary")
  have_func("FreeLibrary")
  have_func("GetProcAddress")
else
  exit(0)
end

method(:have_func).arity == 1 or have_func("rb_str_cat2", "ruby.h")
if method(:have_func).arity == 1 or !have_func("rb_block_given_p", "ruby.h")
    $dlconfig_h << "#define rb_block_given_p rb_iterator_p\n"
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
MAX_CBARG = #{max_cbarg}
MAX_CBENT = #{max_cbent}
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

create_makefile('dl')
rescue SystemExit
  # do nothing
end
