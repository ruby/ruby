# Parse built-in script and make rbinc file

require 'open3'
require 'stringio'
require 'strscan'
require_relative 'ruby_vm/helpers/c_escape'

SUBLIBS = {}
REQUIRED = {}

# ruby mk_builtin_loader.rb TARGET_FILE.rb
# #=> generate TARGET_FILE.rbinc
#

LOCALS_DB = {} # [method_name, first_line] = locals

def collect_builtin file, bs, inlines
  stdout, stderr, status = Open3.capture3(File.expand_path("collect_builtins", __dir__), file)

  unless status.success?
    warn(stderr)
    exit(1)
  end

  scanner = StringScanner.new(stdout)
  while (command = scanner.scan(/BUILTIN|INLINE|REQUIRE/))
    case command
    when "BUILTIN"
      scanner.scan(/ primitive_name=(.+?) argc=(\d+) cfunction_name=(.+?)\n/) or raise "unexpected format"

      primitive_name, argc, cfunction_name = scanner.captures
      argc = argc.to_i

      if bs[primitive_name] && bs[primitive_name] != [argc, cfunction_name]
        raise "same builtin function \"#{primitive_name}\", but different arity (was #{bs[primitive_name]} but #{argc})"
      end

      bs[primitive_name] = [argc, cfunction_name]
    when "INLINE"
      scanner.scan(/ key=(.+?) lineno=(\d+) text=((?:.|\n)+?) locals.name=(.*?) locals.lineno=(\d+) primitive_name=(.+?)\n/) or raise "unexpected format"

      key, lineno, text, locals_name, locals_lineno, primitive_name = scanner.captures
      lineno = lineno.to_i
      locals_lineno = locals_lineno.to_i

      inline = [lineno, text, nil, primitive_name]
      inline[2] = LOCALS_DB[[locals_name, locals_lineno]] if locals_lineno != 0

      if inlines.key?(key)
        found = 1000.times.find { |i| !inlines.key?("#{key}_#{i}") }
        raise "too many functions in same line..." unless found
        key = "#{key}_#{found}"
      end

      inlines[key] = inline
    when "REQUIRE"
      scanner.scan(/ (.+)\n/) or raise "unexpected format"
      sublib = scanner[1]

      if File.exist?(f = File.join(@dir, sublib)+".rb")
        puts "- #{@base}.rb requires #{sublib}"
        if REQUIRED[sublib]
          warn "!!! #{sublib} is required from #{REQUIRED[sublib]} already; ignored"
        else
          REQUIRED[sublib] = @base
          (SUBLIBS[@base] ||= []) << sublib
        end
        ARGV.push(f)
      end
    end
  end
end

def collect_iseq iseq_ary
  # iseq_ary.each_with_index{|e, i| p [i, e]}
  label = iseq_ary[5]
  first_line = iseq_ary[8]
  type = iseq_ary[9]
  locals = iseq_ary[10]
  insns = iseq_ary[13]

  if type == :method
    LOCALS_DB[[label, first_line].freeze] = locals
  end

  insns.each{|insn|
    case insn
    when Integer
      # ignore
    when Array
      # p insn.shift # insn name
      insn.each{|op|
        if Array === op && op[0] == "YARVInstructionSequence/SimpleDataFormat"
          collect_iseq op
        end
      }
    end
  }
end

def generate_cexpr(ofile, lineno, line_file, body_lineno, text, locals, func_name)
  f = StringIO.new

  # Avoid generating fetches of lvars we don't need. This is imperfect as it
  # will match text inside strings or other false positives.
  local_candidates = text.scan(/[a-zA-Z_][a-zA-Z0-9_]*/)

  f.puts '{'
  lineno += 1
  # locals is nil outside methods
  locals&.reverse_each&.with_index{|param, i|
    next unless Symbol === param
    next unless local_candidates.include?(param.to_s)
    f.puts "VALUE *const #{param}__ptr = (VALUE *)&ec->cfp->ep[#{-3 - i}];"
    f.puts "MAYBE_UNUSED(const VALUE) #{param} = *#{param}__ptr;"
    lineno += 1
  }
  f.puts "#line #{body_lineno} \"#{line_file}\""
  lineno += 1

  f.puts text
  lineno += text.count("\n") + 1

  f.puts "#line #{lineno + 2} \"#{ofile}\"" # TODO: restore line number.
  f.puts "}"
  f.puts
  lineno += 3

  return lineno, f.string
end

def mk_builtin_header file
  @dir = File.dirname(file)
  base = File.basename(file, '.rb')
  @base = base
  ofile = "#{file}inc"

  # bs = { func_name => argc }
  collect_iseq RubyVM::InstructionSequence.compile_file(file).to_a
  collect_builtin(file, bs = {}, inlines = {})

  begin
    f = File.open(ofile, 'w')
  rescue SystemCallError # EACCES, EPERM, EROFS, etc.
    # Fall back to the current directory
    f = File.open(File.basename(ofile), 'w')
  end
  begin
    if File::ALT_SEPARATOR
      file = file.tr(File::ALT_SEPARATOR, File::SEPARATOR)
      ofile = ofile.tr(File::ALT_SEPARATOR, File::SEPARATOR)
    end
    lineno = __LINE__
    f.puts "// -*- c -*-"
    f.puts "// DO NOT MODIFY THIS FILE DIRECTLY."
    f.puts "// auto-generated file"
    f.puts "//   by #{__FILE__}"
    f.puts "//   with #{file}"
    f.puts '#include "internal/compilers.h"     /* for MAYBE_UNUSED */'
    f.puts '#include "internal/warnings.h"      /* for COMPILER_WARNING_PUSH */'
    f.puts '#include "ruby/ruby.h"              /* for VALUE */'
    f.puts '#include "builtin.h"                /* for RB_BUILTIN_FUNCTION */'
    f.puts 'struct rb_execution_context_struct; /* in vm_core.h */'
    f.puts
    lineno = __LINE__ - lineno - 1
    line_file = file

    inlines.each{|cfunc_name, (body_lineno, text, locals, func_name)|
      if String === cfunc_name
        f.puts "static VALUE #{cfunc_name}(struct rb_execution_context_struct *ec, const VALUE self)"
        lineno += 1
        lineno, str = generate_cexpr(ofile, lineno, line_file, body_lineno, text, locals, func_name)
        f.write str
      else
        # cinit!
        f.puts "#line #{body_lineno} \"#{line_file}\""
        lineno += 1
        f.puts text
        lineno += text.count("\n") + 1
        f.puts "#line #{lineno + 2} \"#{ofile}\"" # TODO: restore line number.
        lineno += 1
      end
    }

    if SUBLIBS[base]
      f.puts "// sub libraries"
      SUBLIBS[base].each do |sub|
        f.puts %[#include #{(sub+".rbinc").dump}]
      end
      f.puts
    end

    f.puts "void Init_builtin_#{base}(void)"
    f.puts "{"

    table = "#{base}_table"
    f.puts "  // table definition"
    f.puts "  static const struct rb_builtin_function #{table}[] = {"
    bs.each.with_index{|(func, (argc, cfunc_name)), i|
      f.puts "    RB_BUILTIN_FUNCTION(#{i}, #{func}, #{cfunc_name}, #{argc}),"
    }
    f.puts "    RB_BUILTIN_FUNCTION(-1, NULL, NULL, 0),"
    f.puts "  };"

    f.puts
    f.puts "  // arity_check"
    f.puts "COMPILER_WARNING_PUSH"
    f.puts "#if GCC_VERSION_SINCE(5, 1, 0) || defined __clang__"
    f.puts "COMPILER_WARNING_ERROR(-Wincompatible-pointer-types)"
    f.puts "#endif"
    bs.each{|func, (argc, cfunc_name)|
      f.puts "  if (0) rb_builtin_function_check_arity#{argc}(#{cfunc_name});"
    }
    f.puts "COMPILER_WARNING_POP"

    if SUBLIBS[base]
      f.puts
      f.puts "  // sub libraries"
      SUBLIBS[base].each do |sub|
        f.puts "  Init_builtin_#{sub}();"
      end
    end

    f.puts
    f.puts "  // load"
    f.puts "  rb_load_with_builtin_functions(#{base.dump}, #{table});"

    f.puts "}"
  ensure
    f.close
  end
end

ARGV.each{|file|
  # feature.rb => load_feature.inc
  mk_builtin_header file
}
