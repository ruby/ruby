# Copyright (C) 2017 Vladimir Makarov, <vmakarov@redhat.com>
# This is a script to transform functions to static inline.
# Usage: transform_mjit_header.rb <c-compiler> <header file> <out>

require 'fileutils'
require 'tempfile'

PROGRAM = File.basename($0, ".*")

module MJITHeader
  ATTR_VALUE_REGEXP  = /[^()]|\([^()]*\)/
  ATTR_REGEXP        = /__attribute__\s*\(\(#{ATTR_VALUE_REGEXP}*\)\)/
  # Example:
  #   VALUE foo(int bar)
  #   VALUE __attribute__ ((foo)) bar(int baz)
  #   __attribute__ ((foo)) VALUE bar(int baz)
  FUNC_HEADER_REGEXP = /\A[^\[{(]*(\s*#{ATTR_REGEXP})*[^\[{(]*\((#{ATTR_REGEXP}|[^()])*\)(\s*#{ATTR_REGEXP})*\s*/
  TARGET_NAME_REGEXP = /\A(rb|ruby|vm|insn|attr|Init)_/

  # Predefined macros for compilers which are already supported by MJIT.
  # We're going to support cl.exe too (WIP) but `cl.exe -E` can't produce macro.
  SUPPORTED_CC_MACROS = [
    '__GNUC__', # gcc
    '__clang__', # clang
  ]

  # These macros are relied on this script's transformation
  PREFIXED_MACROS = [
    'ALWAYS_INLINE',
    'inline',
  ]

  # For MinGW's ras.h. Those macros have its name in its definition and can't be preprocessed multiple times.
  RECURSIVE_MACROS = %w[
    RASCTRYINFO
    RASIPADDR
  ]

  IGNORED_FUNCTIONS = [
    'rb_vm_search_method_slowpath', # This increases the time to compile when inlined. So we use it as external function.
    'rb_equal_opt', # Not used from VM and not compilable
  ]

  ALWAYS_INLINED_FUNCTIONS = [
    'vm_opt_plus',
    'vm_opt_minus',
    'vm_opt_mult',
    'vm_opt_div',
    'vm_opt_mod',
    'vm_opt_neq',
    'vm_opt_lt',
    'vm_opt_le',
    'vm_opt_gt',
    'vm_opt_ge',
    'vm_opt_ltlt',
    'vm_opt_and',
    'vm_opt_or',
    'vm_opt_aref',
    'vm_opt_aset',
    'vm_opt_aref_with',
    'vm_opt_aset_with',
    'vm_opt_not',
    'vm_getinstancevariable',
    'vm_setinstancevariable',
    'vm_setivar',
  ]

  # Return start..stop of last decl in CODE ending STOP
  def self.find_decl(code, stop)
    level = 0
    i = stop
    while i = code.rindex(/[;{}]/, i)
      if level == 0 && stop != i && decl_found?($&, i)
        return decl_start($&, i)..stop
      end
      case $&
      when '}'
        level += 1
      when '{'
        level -= 1
      end
      i -= 1
    end
    nil
  end

  def self.decl_found?(code, i)
    i == 0 || code == ';' || code == '}'
  end

  def self.decl_start(code, i)
    if i == 0 && code != ';' && code != '}'
      0
    else
      i + 1
    end
  end

  # Given DECL return the name of it, nil if failed
  def self.decl_name_of(decl)
    ident_regex = /\w+/
    decl = decl.gsub(/^#.+$/, '') # remove macros
    reduced_decl = decl.gsub(ATTR_REGEXP, '') # remove attributes
    su1_regex = /{[^{}]*}/
    su2_regex = /{([^{}]|#{su1_regex})*}/
    su3_regex = /{([^{}]|#{su2_regex})*}/ # 3 nested structs/unions is probably enough
    reduced_decl.gsub!(su3_regex, '') # remove structs/unions in the header
    id_seq_regex = /\s*(#{ident_regex}(\s+|\s*[*]+\s*))*/
    # Process function header:
    match = /\A#{id_seq_regex}(?<name>#{ident_regex})\s*\(/.match(reduced_decl)
    return match[:name] if match
    # Process non-function declaration:
    reduced_decl.gsub!(/\s*=[^;]+(?=;)/, '') # remove initialization
    match = /#{id_seq_regex}(?<name>#{ident_regex})/.match(reduced_decl);
    return match[:name] if match
    nil
  end

  # Return true if CC with CFLAGS compiles successfully the current code.
  # Use STAGE in the message in case of a compilation failure
  def self.check_code!(code, cc, cflags, stage)
    with_code(code) do |path|
      cmd = "#{cc} #{cflags} #{path}"
      out = IO.popen(cmd, err: [:child, :out], &:read)
      unless $?.success?
        STDERR.puts "error in #{stage} header file:\n#{out}"
        exit false
      end
    end
  end

  # Remove unpreprocessable macros
  def self.remove_harmful_macros!(code)
    code.gsub!(/^#define #{Regexp.union(RECURSIVE_MACROS)} .*$/, '')
  end

  # -dD outputs those macros, and it produces redefinition warnings or errors
  # This assumes common.mk passes `-DMJIT_HEADER` first when it creates rb_mjit_header.h.
  def self.remove_predefined_macros!(code)
    code.sub!(/\A(#define [^\n]+|\n)*(#define MJIT_HEADER 1\n)/, '\2')
  end

  # Return [macro, others]. But others include PREFIXED_MACROS to be used in code.
  def self.separate_macro_and_code(code)
    code.lines.partition do |l|
      l.start_with?('#') && PREFIXED_MACROS.all? { |m| !l.start_with?("#define #{m}") }
    end.map! { |lines| lines.join('') }
  end

  def self.write(code, out)
    # create with strict permission, then will install proper
    # permission
    FileUtils.mkdir_p(File.dirname(out), mode: 0700)
    File.binwrite("#{out}.new", code, perm: 0600)
    FileUtils.mv("#{out}.new", out)
  end

  # Note that this checks runruby. This conservatively covers platform names.
  def self.windows?
    RUBY_PLATFORM =~ /mswin|mingw|msys/
  end

  def self.cl_exe?(cc)
    cc =~ /\Acl(\z| |\.exe)/
  end

  # If code has macro which only supported compilers predefine, return true.
  def self.supported_header?(code)
    SUPPORTED_CC_MACROS.any? { |macro| code =~ /^#\s*define\s+#{Regexp.escape(macro)}\b/ }
  end

  # This checks if syntax check outputs one of the following messages.
  #    "error: conflicting types for 'restrict'"
  #    "error: redefinition of parameter 'restrict'"
  # If it's true, this script regards platform as AIX or Solaris and adds -std=c99 as workaround.
  def self.conflicting_types?(code, cc, cflags)
    with_code(code) do |path|
      cmd = "#{cc} #{cflags} #{path}"
      out = IO.popen(cmd, err: [:child, :out], &:read)
      !$?.success? &&
        (out.match?(/error: conflicting types for '[^']+'/) ||
         out.match?(/error: redefinition of parameter '[^']+'/))
    end
  end

  def self.with_code(code)
    # for `system_header` pragma which can't be in the main file.
    Tempfile.open(['', '.h'], mode: File::BINARY) do |f|
      f.puts code
      f.close
      Tempfile.open(['', '.c'], mode: File::BINARY) do |c|
        c.puts <<SRC
#include "#{f.path}"
SRC
        c.close
        return yield(c.path)
      end
    end
  end
  private_class_method :with_code
end

if ARGV.size != 3
  abort "Usage: #{$0} <c-compiler> <header file> <out>"
end

cc      = ARGV[0]
code    = File.binread(ARGV[1]) # Current version of the header file.
outfile = ARGV[2]
if MJITHeader.cl_exe?(cc)
  cflags = '-DMJIT_HEADER -Zs'
else
  cflags = '-S -DMJIT_HEADER -fsyntax-only -Werror=implicit-function-declaration -Werror=implicit-int -Wfatal-errors'
end

if !MJITHeader.cl_exe?(cc) && !MJITHeader.supported_header?(code)
  puts "This compiler (#{cc}) looks not supported for MJIT. Giving up to generate MJIT header."
  MJITHeader.write("#error MJIT does not support '#{cc}' yet", outfile)
  exit
end

MJITHeader.remove_predefined_macros!(code)

if MJITHeader.windows? # transformation is broken with Windows headers for now
  MJITHeader.remove_harmful_macros!(code)
  MJITHeader.check_code!(code, cc, cflags, 'initial')
  puts "\nSkipped transforming external functions to static on Windows."
  MJITHeader.write(code, outfile)
  exit
end

macro, code = MJITHeader.separate_macro_and_code(code) # note: this does not work on MinGW
code = <<header + code
#ifdef __GNUC__
# pragma GCC system_header
#endif
header
code_to_check = "#{code}#{macro}" # macro should not affect code again

if MJITHeader.conflicting_types?(code_to_check, cc, cflags)
  cflags = "#{cflags} -std=c99" # For AIX gcc
end

# Check initial file correctness in the manner of final output.
MJITHeader.check_code!(code_to_check, cc, cflags, 'initial')
puts "\nTransforming external functions to static:"

stop_pos     = -1
extern_names = []

# This loop changes function declarations to static inline.
while (decl_range = MJITHeader.find_decl(code, stop_pos))
  stop_pos = decl_range.begin - 1
  decl = code[decl_range]
  decl_name = MJITHeader.decl_name_of(decl)

  if MJITHeader::IGNORED_FUNCTIONS.include?(decl_name) && /#{MJITHeader::FUNC_HEADER_REGEXP}{/.match(decl)
    puts "#{PROGRAM}: changing definition of '#{decl_name}' to declaration"
    code[decl_range] = decl.sub(/{.+}/m, ';')
  elsif MJITHeader::ALWAYS_INLINED_FUNCTIONS.include?(decl_name) && match = /#{MJITHeader::FUNC_HEADER_REGEXP}{/.match(decl)
    header = match[0].sub(/{\z/, '').strip
    header = "static inline #{header.sub(/\A((static|inline) )+/, '')}"
    decl[match.begin(0)...match.end(0)] = '{' # remove header
    code[decl_range] = "\nALWAYS_INLINE(#{header});\n#{header} #{decl}"
  elsif extern_names.include?(decl_name) && (decl =~ /#{MJITHeader::FUNC_HEADER_REGEXP};/)
    decl.sub!(/(extern|static|inline) /, ' ')
    unless decl_name =~ /\Aattr_\w+_\w+\z/ # skip too-many false-positive warnings in insns_info.inc.
      puts "#{PROGRAM}: making declaration of '#{decl_name}' static inline"
    end

    code[decl_range] = "static inline #{decl}"
  elsif (match = /#{MJITHeader::FUNC_HEADER_REGEXP}{/.match(decl)) && (header = match[0]) !~ /static/
    unless decl_name.match(MJITHeader::TARGET_NAME_REGEXP)
      puts "#{PROGRAM}: SKIPPED to transform #{decl_name}"
      next
    end

    extern_names << decl_name
    decl[match.begin(0)...match.end(0)] = ''

    if decl =~ /\bstatic\b/
      puts "warning: a static decl inside external definition of '#{decl_name}'"
    end

    header.sub!(/(extern|inline) /, ' ')
    unless decl_name =~ /\Aattr_\w+_\w+\z/ # skip too-many false-positive warnings in insns_info.inc.
      puts "#{PROGRAM}: making external definition of '#{decl_name}' static inline"
    end
    code[decl_range] = "static inline #{header}#{decl}"
  end
end

code << macro

# Check the final file correctness
MJITHeader.check_code!(code, cc, cflags, 'final')

MJITHeader.write(code, outfile)
