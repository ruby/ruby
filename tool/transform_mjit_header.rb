# Copyright (C) 2017 Vladimir Makarov, <vmakarov@redhat.com>
# This is a script to transform functions to static inline.
# Usage: transform_mjit_header.rb <c-compiler> <header file> <out>

require 'fileutils'
require 'tempfile'

module MJITHeader
  ATTR_VALUE_REGEXP  = /[^()]|\([^()]*\)/
  ATTR_REGEXP        = /__attribute__\s*\(\((#{ATTR_VALUE_REGEXP})*\)\)/
  FUNC_HEADER_REGEXP = /\A(\s*#{ATTR_REGEXP})*[^\[{(]*\((#{ATTR_REGEXP}|[^()])*\)(\s*#{ATTR_REGEXP})*\s*/

  # For MinGW's ras.h. Those macros have its name in its definition and can't be preprocessed multiple times.
  RECURSIVE_MACROS = %w[
    RASCTRYINFO
    RASIPADDR
  ]

  IGNORED_FUNCTIONS = [
    'vm_search_method', # This increases the time to compile when inlined. So we use it as external function.
    'rb_equal_opt', # Not used from VM and not compilable
  ]

  # Return start..stop of last decl in CODE ending STOP
  def self.find_decl(code, stop)
    level = 0
    stop.downto(0) do |i|
      if level == 0 && stop != i && decl_found?(code, i)
        return decl_start(code, i)..stop
      elsif code[i] == '}'
        level += 1
      elsif code[i] == '{'
        level -= 1
      end
    end
    0..-1
  end

  def self.decl_found?(code, i)
    i == 0 || code[i] == ';' || code[i] == '}'
  end

  def self.decl_start(code, i)
    if i == 0 && code[i] != ';' && code[i] != '}'
      0
    else
      i + 1
    end
  end

  # Given DECL return the name of it, nil if failed
  def self.decl_name_of(decl)
    ident_regex = /\w+/
    decl = decl.gsub(/^#.+$/, '') # remove macros
    reduced_decl = decl.gsub(/#{ATTR_REGEXP}/, '') # remove attributes
    su1_regex = /{[^{}]*}/
    su2_regex = /{([^{}]|su1_regex)*}/
    su3_regex = /{([^{}]|su2_regex)*}/ # 3 nested structs/unions is probably enough
    reduced_decl.gsub!(/#{su3_regex}/, '') # remove strutcs/unions in the header
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
  def self.check_code!(code, cc, cflags, stage:)
    Tempfile.create(['', '.c']) do |f|
      f.puts code
      f.close
      unless system("#{cc} #{cflags} #{f.path} 2>#{File::NULL}")
        STDERR.puts "error in #{stage} header file:"
        system("#{cc} #{cflags} #{f.path}")
        exit 1
      end
    end
  end

  # Remove unpreprocessable macros
  def self.remove_harmful_macros!(code)
    code.gsub!(/^#define #{Regexp.union(RECURSIVE_MACROS)} .*$/, '')
  end

  # -dD outputs those macros, and it produces redefinition warnings
  def self.remove_default_macros!(code)
    code.gsub!(/^#define __STDC_.+$/, '')
    code.gsub!(/^#define assert\([^\)]+\) .+$/, '')
  end

  # This makes easier to process code
  def self.separate_macro_and_code(code)
    code.lines.partition { |l| !l.start_with?('#') }.flatten.join('')
  end

  def self.write(code, out:)
    FileUtils.mkdir_p(File.dirname(out))
    File.write("#{out}.new", code)
    FileUtils.mv("#{out}.new", out)
  end

  # Note that this checks runruby. This conservatively covers platform names.
  def self.windows?
    RUBY_PLATFORM =~ /mswin|mingw|msys/
  end
end

if ARGV.size != 3
  STDERR.puts 'Usage: transform_mjit_header.rb <c-compiler> <header file> <out>'
  exit 1
end

cc      = ARGV[0]
code    = File.read(ARGV[1]) # Current version of the header file.
outfile = ARGV[2]
if cc =~ /\Acl(\z| |\.exe)/
  cflags = '-DMJIT_HEADER -Zs'
else
  cflags = '-S -DMJIT_HEADER -fsyntax-only -Werror=implicit-function-declaration -Werror=implicit-int -Wfatal-errors'
end

if MJITHeader.windows?
  MJITHeader.remove_harmful_macros!(code)
end
MJITHeader.remove_default_macros!(code)

# Check initial file correctness
MJITHeader.check_code!(code, cc, cflags, stage: 'initial')

if MJITHeader.windows? # transformation is broken with Windows headers for now
  STDERR.puts "\nSkipped transforming external functions to static on Windows."
  MJITHeader.write(code, out: outfile)
  exit 0
end
STDERR.puts "\nTransforming external functions to static:"

code = MJITHeader.separate_macro_and_code(code) # note: this does not work on MinGW
stop_pos     = code.match(/^#/).begin(0) # See `separate_macro_and_code`. This ignores proprocessors.
extern_names = []

# This loop changes function declarations to static inline.
loop do
  decl_range = MJITHeader.find_decl(code, stop_pos)
  break if decl_range.end < 0

  stop_pos = decl_range.begin - 1
  decl = code[decl_range]
  decl_name = MJITHeader.decl_name_of(decl)

  if MJITHeader::IGNORED_FUNCTIONS.include?(decl_name) && /#{MJITHeader::FUNC_HEADER_REGEXP}{/.match(decl)
    STDERR.puts "transform_mjit_header: changing definition of '#{decl_name}' to declaration"
    code[decl_range] = decl.sub(/{.+}/m, ';')
  elsif extern_names.include?(decl_name) && (decl =~ /#{MJITHeader::FUNC_HEADER_REGEXP};/)
    decl.sub!(/(extern|static|inline) /, ' ')
    STDERR.puts "transform_mjit_header: making declaration of '#{decl_name}' static inline"

    code[decl_range] = "static inline #{decl}"
  elsif (match = /#{MJITHeader::FUNC_HEADER_REGEXP}{/.match(decl)) && (header = match[0]) !~ /static/
    extern_names << decl_name
    decl[match.begin(0)...match.end(0)] = ''

    if decl =~ /static/
      STDERR.puts "warning: a static decl inside external definition of '#{decl_name}'"
    end

    header.sub!(/(extern|inline) /, ' ')
    STDERR.puts "transform_mjit_header: making external definition of '#{decl_name}' static inline"
    code[decl_range] = "static inline #{header}#{decl}"
  end
end

# Check the final file correctness
MJITHeader.check_code!(code, cc, cflags, stage: 'final')

MJITHeader.write(code, out: outfile)
