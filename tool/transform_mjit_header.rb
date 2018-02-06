# Copyright (C) 2017 Vladimir Makarov, <vmakarov@redhat.com>
# This is a script to transform functions to static inline.
# Usage: transform_mjit_header.rb <c-compiler> <header file> <out>

require 'fileutils'
require 'tempfile'

PROGRAM = File.basename($0, ".*")

module MJITHeader
  ATTR_VALUE_REGEXP  = /[^()]|\([^()]*\)/
  ATTR_REGEXP        = /__attribute__\s*\(\(#{ATTR_VALUE_REGEXP}*\)\)/
  FUNC_HEADER_REGEXP = /\A(\s*#{ATTR_REGEXP})*[^\[{(]*\((#{ATTR_REGEXP}|[^()])*\)(\s*#{ATTR_REGEXP})*\s*/
  TARGET_NAME_REGEXP = /\A(rb|ruby|vm|insn|attr)_/

  # For MinGW's ras.h. Those macros have its name in its definition and can't be preprocessed multiple times.
  RECURSIVE_MACROS = %w[
    RASCTRYINFO
    RASIPADDR
  ]

  IGNORED_FUNCTIONS = [
    'vm_search_method_slowpath', # This increases the time to compile when inlined. So we use it as external function.
    'rb_equal_opt', # Not used from VM and not compilable
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
    Tempfile.open(['', '.c'], mode: File::BINARY) do |f|
      f.puts code
      f.close
      cmd = "#{cc} #{cflags} #{f.path}"
      unless system(cmd, err: File::NULL)
        out = IO.popen(cmd, err: [:child, :out], &:read)
        STDERR.puts "error in #{stage} header file:\n#{out}"

        if match = out.match(/error: conflicting types for '(?<name>[^']+)'/)
          unless (related_lines = code.lines.grep(/#{match[:name]}/)).empty?
            STDERR.puts "possibly related lines:\n#{related_lines.join("\n")}"
          end
        end
        exit false
      end
    end
  end

  # Remove unpreprocessable macros
  def self.remove_harmful_macros!(code)
    code.gsub!(/^#define #{Regexp.union(RECURSIVE_MACROS)} .*$/, '')
  end

  # -dD outputs those macros, and it produces redefinition warnings or errors
  def self.remove_predefined_macros!(code)
    code.sub!(/\A(#define [^\n]+|\n)*(#define MJIT_HEADER 1\n)/, '\2')
  end

  # This makes easier to process code
  def self.separate_macro_and_code(code)
    code.lines.partition { |l| l.start_with?('#') }.map! {|lines| lines.join('')}
  end

  def self.write(code, out)
    FileUtils.mkdir_p(File.dirname(out))
    File.binwrite("#{out}.new", code)
    FileUtils.mv("#{out}.new", out)
  end

  # Note that this checks runruby. This conservatively covers platform names.
  def self.windows?
    RUBY_PLATFORM =~ /mswin|mingw|msys/
  end
end

if ARGV.size != 3
  abort "Usage: #{$0} <c-compiler> <header file> <out>"
end

cc      = ARGV[0]
code    = File.binread(ARGV[1]) # Current version of the header file.
outfile = ARGV[2]
if cc =~ /\Acl(\z| |\.exe)/
  cflags = '-DMJIT_HEADER -Zs'
else
  cflags = '-S -DMJIT_HEADER -fsyntax-only -Werror=implicit-function-declaration -Werror=implicit-int -Wfatal-errors'
end

if MJITHeader.windows?
  MJITHeader.remove_harmful_macros!(code)
end
MJITHeader.remove_predefined_macros!(code)

if MJITHeader.windows? # transformation is broken with Windows headers for now
  MJITHeader.check_code!(code, cc, cflags, 'initial')
  puts "\nSkipped transforming external functions to static on Windows."
  MJITHeader.write(code, outfile)
  exit
else
  macro, code = MJITHeader.separate_macro_and_code(code) # note: this does not work on MinGW

  # Check initial file correctness in the manner of final output.
  MJITHeader.check_code!("#{code}#{macro}", cc, cflags, 'initial')
end
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
