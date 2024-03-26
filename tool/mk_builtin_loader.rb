# Parse built-in script and make rbinc file

require 'ripper'
require 'stringio'
require_relative 'ruby_vm/helpers/c_escape'

SUBLIBS = {}
REQUIRED = {}
BUILTIN_ATTRS = %w[leaf inline_block use_block]

def string_literal(lit, str = [])
  while lit
    case lit.first
    when :string_concat, :string_embexpr, :string_content
      _, *lit = lit
      lit.each {|s| string_literal(s, str)}
      return str
    when :string_literal
      _, lit = lit
    when :@tstring_content
      str << lit[1]
      return str
    else
      raise "unexpected #{lit.first}"
    end
  end
end

# e.g. [:symbol_literal, [:symbol, [:@ident, "inline", [19, 21]]]]
def symbol_literal(lit)
  symbol_literal, symbol_lit = lit
  raise "#{lit.inspect} was not :symbol_literal" if symbol_literal != :symbol_literal
  symbol, ident_lit = symbol_lit
  raise "#{symbol_lit.inspect} was not :symbol" if symbol != :symbol
  ident, symbol_name, = ident_lit
  raise "#{ident.inspect} was not :@ident" if ident != :@ident
  symbol_name
end

def inline_text argc, arg1
  raise "argc (#{argc}) of inline! should be 1" unless argc == 1
  arg1 = string_literal(arg1)
  raise "1st argument should be string literal" unless arg1
  arg1.join("").rstrip
end

def inline_attrs(args)
  raise "args was empty" if args.empty?
  args.each do |arg|
    attr = symbol_literal(arg)
    unless BUILTIN_ATTRS.include?(attr)
      raise "attr (#{attr}) was not in: #{BUILTIN_ATTRS.join(', ')}"
    end
  end
end

def make_cfunc_name inlines, name, lineno
  case name
  when /\[\]/
    name = '_GETTER'
  when /\[\]=/
    name = '_SETTER'
  else
    name = name.tr('!?', 'EP')
  end

  base = "builtin_inline_#{name}_#{lineno}"
  if inlines[base]
    1000.times{|i|
      name = "#{base}_#{i}"
      return name unless inlines[name]
    }
    raise "too many functions in same line..."
  else
    base
  end
end

def collect_locals tree
  _type, name, (line, _cols) = tree
  if locals = LOCALS_DB[[name, line]]
    locals
  else
    if false # for debugging
      pp LOCALS_DB
      raise "not found: [#{name}, #{line}]"
    end
  end
end

def collect_builtin base, tree, name, bs, inlines, locals = nil
  while tree
    recv = sep = mid = args = nil
    case tree.first
    when :def
      locals = collect_locals(tree[1])
      tree = tree[3]
      next
    when :defs
      locals = collect_locals(tree[3])
      tree = tree[5]
      next
    when :class
      name = 'class'
      tree = tree[3]
      next
    when :sclass, :module
      name = 'class'
      tree = tree[2]
      next
    when :method_add_arg
      _method_add_arg, mid, (_arg_paren, args) = tree
      case mid.first
      when :call
        _, recv, sep, mid = mid
      when :fcall
        _, mid = mid
      else
        mid = nil
      end
      # w/  trailing comma: [[:method_add_arg, ...]]
      # w/o trailing comma: [:args_add_block, [[:method_add_arg, ...]], false]
      if args && args.first == :args_add_block
        args = args[1]
      end
    when :vcall
      _, mid = tree
    when :command               # FCALL
      _, mid, (_, args) = tree
    when :call, :command_call   # CALL
      _, recv, sep, mid, (_, args) = tree
    end

    if mid
      raise "unknown sexp: #{mid.inspect}" unless %i[@ident @const].include?(mid.first)
      _, mid, (lineno,) = mid
      if recv
        func_name = nil
        case recv.first
        when :var_ref
          _, recv = recv
          if recv.first == :@const and recv[1] == "Primitive"
            func_name = mid.to_s
          end
        when :vcall
          _, recv = recv
          if recv.first == :@ident and recv[1] == "__builtin"
            func_name = mid.to_s
          end
        end
        collect_builtin(base, recv, name, bs, inlines) unless func_name
      else
        func_name = mid[/\A__builtin_(.+)/, 1]
      end
      if func_name
        cfunc_name = func_name
        args.pop unless (args ||= []).last
        argc = args.size

        if /(.+)[\!\?]\z/ =~ func_name
          case $1
          when 'attr'
            # Compile-time validation only. compile.c will parse them.
            inline_attrs(args)
            break
          when 'cstmt'
            text = inline_text argc, args.first

            func_name = "_bi#{lineno}"
            cfunc_name = make_cfunc_name(inlines, name, lineno)
            inlines[cfunc_name] = [lineno, text, locals, func_name]
            argc -= 1
          when 'cexpr', 'cconst'
            text = inline_text argc, args.first
            code = "return #{text};"

            func_name = "_bi#{lineno}"
            cfunc_name = make_cfunc_name(inlines, name, lineno)

            locals = [] if $1 == 'cconst'
            inlines[cfunc_name] = [lineno, code, locals, func_name]
            argc -= 1
          when 'cinit'
            text = inline_text argc, args.first
            func_name = nil # required
            inlines[inlines.size] = [lineno, text, nil, nil]
            argc -= 1
          when 'mandatory_only'
            func_name = nil
          when 'arg'
            argc == 1 or raise "unexpected argument number #{argc}"
            (arg = args.first)[0] == :symbol_literal or raise "symbol literal expected #{args}"
            (arg = arg[1])[0] == :symbol or raise "symbol expected #{arg}"
            (var = arg[1] and var = var[1]) or raise "argument name expected #{arg}"
            func_name = nil
          end
        end

        if bs[func_name] &&
           bs[func_name] != [argc, cfunc_name]
          raise "same builtin function \"#{func_name}\", but different arity (was #{bs[func_name]} but #{argc})"
        end

        bs[func_name] = [argc, cfunc_name] if func_name
      elsif /\Arequire(?:_relative)\z/ =~ mid and args.size == 1 and
           (arg1 = args[0])[0] == :string_literal and
           (arg1 = arg1[1])[0] == :string_content and
           (arg1 = arg1[1])[0] == :@tstring_content and
           sublib = arg1[1]
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
      break unless tree = args
    end

    tree.each do |t|
      collect_builtin base, t, name, bs, inlines, locals if Array === t
    end
    break
  end
end

# ruby mk_builtin_loader.rb TARGET_FILE.rb
# #=> generate TARGET_FILE.rbinc
#

LOCALS_DB = {} # [method_name, first_line] = locals

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
  code = File.read(file)
  collect_iseq RubyVM::InstructionSequence.compile(code).to_a
  collect_builtin(base, Ripper.sexp(code), 'top', bs = {}, inlines = {})

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
