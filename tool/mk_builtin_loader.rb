# Parse built-in script and make rbinc file

require 'json'
require 'open3'
require 'stringio'
require_relative 'ruby_vm/helpers/c_escape'

SUBLIBS = {}
REQUIRED = {}
BUILTIN_ATTRS = %w[leaf inline_block use_block c_trace]

module CompileWarning
  @@warnings = 0

  def warn(message)
    @@warnings += 1
    super
  end

  def self.reset
    w, @@warnings = @@warnings, 0
    w.nonzero?
  end
end

Warning.extend CompileWarning

# ruby mk_builtin_loader.rb path/to/dump/ast TARGET_FILE.rb
# #=> generate TARGET_FILE.rbinc
#

LOCALS_DB = {} # [method_name, first_line] = locals

# Extract the contents of the given string node.
def extract_string_literal(node)
  case node["type"]
  when "StringNode"
    node["unescaped"]
  when "InterpolatedStringNode"
    node["parts"].map { |part| extract_string_literal(part) }.join
  else
    raise "unexpected #{node["type"]}"
  end
end

# Retrieve the line number of the given node in the source.
def line_number(source, node)
  source.b.byteslice(0, node["location"]["start"]).count("\n") + 1
end

def visit_call_node(source, node, name, locals, requires, bs, inlines)
  # If this is a call to require or require relative with a single string node
  # argument, then we will attempt to find the file that is being required and
  # add it to the files that should be processed.
  if %w[require require_relative].include?(node["name"]) && !node["arguments"].nil? && (argument = node["arguments"]["arguments"][0])["type"] == "StringNode"
    requires << argument["unescaped"]
    return true
  end

  primitive_name = nil

  if (!node["receiver"].nil? && node["receiver"]["type"] == "ConstantReadNode" && node["receiver"]["name"] == "Primitive") ||
     (!node["receiver"].nil? && node["receiver"]["type"] == "CallNode" && node["receiver"]["flags"].include?("VARIABLE_CALL") && node["receiver"]["name"] == "__builtin")
    primitive_name = node["name"]
  elsif node["name"].start_with?("__builtin_")
    primitive_name = node["name"][10..-1]
  else
    # If we get here, then this isn't a primitive function call and we can
    # continue the visit.
    return true
  end

  # The name of the C function that we will be calling for this call node. It
  # may change later in this method depending on the type of primitive.
  cfunction_name = primitive_name

  args = node["arguments"].nil? ? [] : node["arguments"]["arguments"]
  argc = args.size

  if primitive_name.match?(/[\!\?]$/)
    case (primitive_macro = primitive_name[0...-1])
    when "arg"
      # This is a call to Primitive.arg!, which expects a single symbol argument
      # detailing the name of the argument.
      raise "unexpected argument number #{argc}" if argc != 1
      raise "symbol literal expected, got #{args[0]["type"]}" if args[0]["type"] != "SymbolNode"
      return true
    when "attr"
      # This is a call to Primitive.attr!, which expects a list of known
      # symbols. We will check that each of the arguments is a symbol and that
      # the symbol is one of the known symbols.
      raise "args was empty" if argc == 0

      args.each do |arg|
        raise "#{arg["type"]} was not a SymbolNode" if arg["type"] != "SymbolNode"
        raise "attr (#{arg["unescaped"]}) was not in: leaf, inline_block, use_block" unless BUILTIN_ATTRS.include?(arg["unescaped"])
      end

      return true
    when "mandatory_only"
      # This is a call to Primitive.mandatory_only?. This method does not
      # require any further processing.
      return true
    when "cstmt", "cexpr", "cconst", "cinit"
      # This is a call to Primitive.cstmt!, Primitive.cexpr!, Primitive.cconst!,
      # or Primitive.cinit!. These methods expect a single string argument that
      # is the C code that should be executed. We will extract the string, emit
      # an inline function, and then continue the visit.
      raise "argc (#{argc}) of inline! should be 1" if argc != 1

      text = extract_string_literal(args[0]).rstrip
      lineno = line_number(source, node)

      case primitive_macro
      when "cstmt"
        cfunction_name = "builtin_inline_#{name}_#{lineno}"
        primitive_name = "_bi#{lineno}"
        inlines << [cfunction_name, lineno, text, locals, primitive_name]
      when "cexpr", "cconst"
        cfunction_name = "builtin_inline_#{name}_#{lineno}"
        primitive_name = "_bi#{lineno}"
        inlines << [cfunction_name, lineno, "return #{text};", primitive_macro == "cexpr" ? locals : nil, primitive_name]
      when "cinit"
        inlines << [inlines.size, lineno, text, nil, nil]
        return true
      end

      argc -= 1
    else
      # This is a call to Primitive that is not a known method, so it must be a
      # regular C function. In this case we do not need any special processing.
    end
  end

  bs << [primitive_name, argc, cfunction_name]
  return true
end

def each_node(root, &blk)
  return unless yield root

  root.each do |key, value|
    next if key == "type" || key == "location"

    if value.is_a?(Hash)
      each_node(value, &blk) if value.key?("type")
    elsif value.is_a?(Array) && value[0].is_a?(Hash)
      value.each { |node| each_node(node, &blk) }
    end
  end
end

def visit_node(source, root, name, locals, requires, bs, inlines)
  each_node(root) do |node|
    case node["type"]
    when "CallNode"
      visit_call_node(source, node, name, locals, requires, bs, inlines)
    when "DefNode"
      lineno = line_number(source, node)
      visit_node(source, node["body"], name, LOCALS_DB[[node["name"], lineno]], requires, bs, inlines) if node["body"]
      false
    when "ClassNode", "ModuleNode", "SingletonClassNode"
      visit_node(source, node["body"], "class", nil, requires, bs, inlines) if node["body"]
      false
    else
      true
    end
  end
end

def collect_builtins(dump_ast, file)
  stdout, stderr, status = Open3.capture3(dump_ast, file)
  unless status.success?
    warn(stderr)
    exit(1)
  end

  source = File.read(file)
  root = JSON.parse(stdout)
  visit_node(source, root, "top", nil, requires = [], builtins = [], inlines = [])

  requires.each do |sublib|
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

  processed_builtins = {}
  builtins.each do |(primitive_name, argc, cfunction_name)|
    if processed_builtins.key?(primitive_name) && processed_builtins[primitive_name] != [argc, cfunction_name]
      raise "same builtin function \"#{primitive_name}\", but different arity (was #{processed_builtins[primitive_name]} but #{argc})"
    end

    processed_builtins[primitive_name] = [argc, cfunction_name]
  end

  processed_inlines = {}
  inlines.each do |(cfunction_name, lineno, text, locals, primitive_name)|
    if processed_inlines.key?(cfunction_name)
      found = 1000.times.find { |i| !processed_inlines.key?("#{cfunction_name}_#{i}") }
      raise "too many functions in same line..." unless found
      cfunction_name = "#{cfunction_name}_#{found}"
    end

    processed_inlines[cfunction_name] = [lineno, text, locals, primitive_name]
  end

  [processed_builtins, processed_inlines]
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
  local_ptrs = []
  local_candidates = text.gsub(/\bLOCAL_PTR\(\K[a-zA-Z_][a-zA-Z0-9_]*(?=\))/) {
    local_ptrs << $&; ''
  }.scan(/[a-zA-Z_][a-zA-Z0-9_]*/)

  f.puts '{'
  lineno += 1
  # locals is nil outside methods
  locals&.reverse_each&.with_index{|param, i|
    next unless Symbol === param
    param = param.to_s
    lvar = local_candidates.include?(param)
    next unless lvar or local_ptrs.include?(param)
    f.puts "VALUE *const #{param}__ptr = (VALUE *)&ec->cfp->ep[#{-3 - i}];"
    f.puts "MAYBE_UNUSED(const VALUE) #{param} = *#{param}__ptr;" if lvar
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

def mk_builtin_header dump_ast, file
  @dir = File.dirname(file)
  base = File.basename(file, '.rb')
  @base = base
  ofile = "#{file}inc"

  begin
    verbose, $VERBOSE = $VERBOSE, true
    collect_iseq RubyVM::InstructionSequence.compile_file(file).to_a
  ensure
    $VERBOSE = verbose
  end
  if warnings = CompileWarning.reset
    raise "#{warnings} warnings in #{file}"
  end

  # bs = { func_name => argc }
  bs, inlines = collect_builtins(dump_ast, file)

  StringIO.open do |f|
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

    begin
      File.write(ofile, f.string)
    rescue SystemCallError # EACCES, EPERM, EROFS, etc.
      # Fall back to the current directory
      File.write(File.basename(ofile), f.string)
    end
  end
end

dump_ast = ARGV.shift
if !File.executable?(dump_ast)
  warn "Could not find #{dump_ast} executable to dump AST."
  exit 1
end

ARGV.each{|file|
  # feature.rb => load_feature.inc
  mk_builtin_header dump_ast, file
}
