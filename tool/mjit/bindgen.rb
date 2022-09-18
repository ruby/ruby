#!/usr/bin/env ruby
# frozen_string_literal: true
require 'etc'
require 'fiddle/import'
require 'set'

unless build_dir = ARGV.first
  abort "Usage: #{$0} BUILD_DIR"
end

if Fiddle::SIZEOF_VOIDP == 8
  arch_bits = 64
else
  arch_bits = 32
end

# Help ffi-clang find libclang
if arch_bits == 64
  # apt install libclang1
  ENV['LIBCLANG'] ||= Dir.glob("/lib/#{RUBY_PLATFORM}-gnu/libclang-*.so*").grep_v(/-cpp/).sort.last
else
  # apt install libclang1:i386
  ENV['LIBCLANG'] ||= Dir.glob("/lib/i386-linux-gnu/libclang-*.so*").sort.last
end
require 'ffi/clang'

class Node < Struct.new(
  :kind,
  :spelling,
  :type,
  :typedef_type,
  :bitwidth,
  :sizeof_type,
  :offsetof,
  :tokens,
  :enum_value,
  :children,
  keyword_init: true,
)
end

class CParser
  def initialize(tokens)
    @tokens = lex(tokens)
    @pos = 0
  end

  def parse
    expression
  end

  private

  def lex(toks)
    toks.map do |tok|
      case tok
      when /\A\d+\z/         then [:NUMBER, tok]
      when /\A0x[0-9a-f]*\z/ then [:NUMBER, tok]
      when '('               then [:LEFT_PAREN, tok]
      when ')'               then [:RIGHT_PAREN, tok]
      when 'unsigned', 'int' then [:TYPE, tok]
      when '<<'              then [:LSHIFT, tok]
      when '>>'              then [:RSHIFT, tok]
      when '-'               then [:MINUS, tok]
      when '+'               then [:PLUS, tok]
      when /\A\w+\z/         then [:IDENT, tok]
      else
        raise "Unknown token: #{tok}"
      end
    end
  end

  def expression
    equality
  end

  def equality
    exp = comparison

    while match(:BANG_EQUAL, :EQUAL_EQUAL)
      operator = previous
      right = comparison
      exp = [:BINARY, operator, exp, right]
    end

    exp
  end

  def comparison
    expr = term

    while match(:GREATER, :GREATER_EQUAL, :LESS, :LESS_EQUAL)
      operator = previous
      right = comparison
      expr = [:BINARY, operator, expr, right]
    end

    expr
  end

  def term
    expr = bitwise

    while match(:MINUS, :PLUS)
      operator = previous
      right = bitwise
      expr = [:BINARY, operator, expr, right]
    end

    expr
  end

  def bitwise
    expr = unary

    while match(:RSHIFT, :LSHIFT)
      operator = previous
      right = unary
      expr = [:BINARY, operator, expr, right]
    end

    expr
  end

  def unary
    if match(:BANG, :MINUS)
      [:UNARY, previous, primary]
    else
      primary
    end
  end

  def primary
    if match(:LEFT_PAREN)
      grouping
    else
      if match(:IDENT)
        [:VAR, previous]
      elsif match(:NUMBER)
        previous
      else
        raise peek.inspect
      end
    end
  end

  def grouping
    if peek.first == :TYPE
      cast = types
      consume(:RIGHT_PAREN)
      exp = [:TYPECAST, cast, unary]
    else
      exp = [:GROUP, expression]
      consume(:RIGHT_PAREN)
    end
    exp
  end

  def consume(tok)
    unless peek.first == tok
      raise "Expected #{tok} but was #{peek}"
    end
    advance
  end

  def types
    list = []
    loop do
      thing = peek
      break unless thing.first == :TYPE
      list << thing
      advance
    end
    list
  end

  def match(*toks)
    advance if peek && toks.grep(peek.first).any?
  end

  def advance
    @pos += 1
    raise("nope") if @pos > @tokens.length
    true
  end

  def peek
    @tokens[@pos]
  end

  def previous
    @tokens[@pos - 1]
  end
end

class ToRuby
  def initialize(enums)
    @enums = enums
  end

  def visit(node)
    send node.first, node
  end

  private

  def GROUP(node)
    "(" + visit(node[1]) + ")"
  end

  def BINARY(node)
    visit(node[2]) + " " + visit(node[1]) + " " + visit(node[3])
  end

  def TYPECAST(node)
    visit node[2]
  end

  def NUMBER(node)
    node[1].to_s
  end

  def UNARY(node)
    visit(node[1]) + visit(node[2])
  end

  def lit(node)
    node.last
  end

  alias MINUS lit
  alias RSHIFT lit
  alias LSHIFT lit

  def IDENT(node)
    if @enums.include?(node.last)
      "self.#{node.last}"
    else
      "unexpected macro token: #{node.last}"
    end
  end

  def VAR(node)
    visit node[1]
  end
end

# Parse a C header with ffi-clang and return Node objects.
# To ease the maintenance, ffi-clang should be used only inside this class.
class HeaderParser
  def initialize(header, cflags:)
    @translation_unit = FFI::Clang::Index.new.parse_translation_unit(
      header, cflags, [], { detailed_preprocessing_record: true }
    )
  end

  def parse
    parse_children(@translation_unit.cursor)
  end

  private

  def parse_children(cursor)
    children = []
    cursor.visit_children do |cursor, _parent|
      child = parse_cursor(cursor)
      if child.kind != :macro_expansion
        children << child
      end
      next :continue
    end
    children
  end

  def parse_cursor(cursor)
    unless cursor.kind.start_with?('cursor_')
      raise "unexpected cursor kind: #{cursor.kind}"
    end
    kind = cursor.kind.to_s.delete_prefix('cursor_').to_sym
    children = parse_children(cursor)

    offsetof = {}
    if kind == :struct
      children.select { |c| c.kind == :field_decl }.each do |child|
        offsetof[child.spelling] = cursor.type.offsetof(child.spelling)
      end
    end

    sizeof_type = nil
    if %i[struct union].include?(kind)
      sizeof_type = cursor.type.sizeof
    end

    tokens = nil
    if kind == :macro_definition
      tokens = @translation_unit.tokenize(cursor.extent).map(&:spelling)
    end

    enum_value = nil
    if kind == :enum_constant_decl
      enum_value = cursor.enum_value
    end

    Node.new(
      kind: kind,
      spelling: cursor.spelling,
      type: cursor.type.spelling,
      typedef_type: cursor.typedef_type.spelling,
      bitwidth: cursor.bitwidth,
      sizeof_type: sizeof_type,
      offsetof: offsetof,
      tokens: tokens,
      enum_value: enum_value,
      children: children,
    )
  end
end

# Convert Node objects to a Ruby binding source.
class BindingGenerator
  DEFAULTS = { '_Bool' => 'CType::Bool.new' }
  DEFAULTS.default_proc = proc { |_h, k| "CType::Stub.new(:#{k})" }

  attr_reader :src

  # @param macros [Array<String>] Imported macros
  # @param enums [Hash{ Symbol => Array<String> }] Imported enum values
  # @param types [Array<String>] Imported types
  # @param ruby_fields [Hash{ Symbol => Array<String> }] Struct VALUE fields that are considered Ruby objects
  def initialize(macros:, enums:, types:, ruby_fields:)
    @src = String.new
    @macros = macros.sort
    @enums = enums.transform_keys(&:to_s).transform_values(&:sort).sort.to_h
    @types = types.sort
    @ruby_fields = ruby_fields.transform_keys(&:to_s)
    @references = Set.new
  end

  def generate(nodes)
    # TODO: Support nested declarations
    nodes_index = nodes.group_by(&:spelling).transform_values(&:last)

    println "require_relative 'c_type'"
    println
    println "module RubyVM::MJIT"

    # Define macros
    @macros.each do |macro|
      unless definition = generate_macro(nodes_index[macro])
        raise "Failed to generate macro: #{macro}"
      end
      println "  def C.#{macro} = #{definition}"
      println
    end

    # Define enum values
    @enums.each do |enum, values|
      values.each do |value|
        unless definition = generate_enum(nodes_index[enum], value)
          raise "Failed to generate enum value: #{value}"
        end
        println "  def C.#{value} = #{definition}"
        println
      end
    end

    # Define types
    @types.each do |type|
      unless definition = generate_node(nodes_index[type])
        raise "Failed to generate type: #{type}"
      end
      println "  def C.#{type}"
      println "@#{type} ||= #{definition}".gsub(/^/, "    ").chomp
      println "  end"
      println
    end

    # Leave a stub for types that are referenced but not targeted
    (@references - @types).each do |type|
      println "  def C.#{type} = #{DEFAULTS[type]}"
      println
    end

    chomp
    println "end"
  end

  private

  def generate_macro(node)
    if node.spelling.start_with?('USE_')
      # Special case: Always force USE_* to be true or false
      case node
      in Node[kind: :macro_definition, tokens: [_, '0' | '1' => token], children: []]
        (Integer(token) == 1).to_s
      end
    else
      # Otherwise, convert a C expression to a Ruby expression when possible
      case node
      in Node[kind: :macro_definition, tokens: tokens, children: []]
        if tokens.first != node.spelling
          raise "unexpected first token: '#{tokens.first}' != '#{node.spelling}'"
        end
        ast = CParser.new(tokens.drop(1)).parse
        ToRuby.new(@enums.values.flatten).visit(ast)
      end
    end
  end

  def generate_enum(node, value)
    case node
    in Node[kind: :enum_decl, children:]
      children.find { |c| c.spelling == value }&.enum_value
    in Node[kind: :typedef_decl, children: [child]]
      generate_enum(child, value)
    end
  end

  # Generate code from a node. Used for constructing a complex nested node.
  # @param node [Node]
  def generate_node(node)
    case node&.kind
    when :struct, :union
      # node.spelling is often empty for union, but we'd like to give it a name when it has one.
      buf = +"CType::#{node.kind.to_s.sub(/\A[a-z]/, &:upcase)}.new(\n"
      buf << "  \"#{node.spelling}\", #{node.sizeof_type},\n"
      node.children.each do |child|
        field_builder = proc do |field, type|
          if node.kind == :struct
            to_ruby = @ruby_fields.fetch(node.spelling, []).include?(field)
            "  #{field}: [#{node.offsetof.fetch(field)}, #{type}#{', true' if to_ruby}],\n"
          else
            "  #{field}: #{type},\n"
          end
        end

        case child
        # BitField is struct-specific. So it must be handled here.
        in Node[kind: :field_decl, spelling:, bitwidth:, children: [_grandchild]] if bitwidth > 0
          buf << field_builder.call(spelling, "CType::BitField.new(#{bitwidth}, #{node.offsetof.fetch(spelling) % 8})")
        # In most cases, we'd like to let generate_type handle the type unless it's "(unnamed ...)".
        in Node[kind: :field_decl, spelling:, type:] if !type.empty? && !type.match?(/\((unnamed|anonymous) [^)]+\)\z/)
          buf << field_builder.call(spelling, generate_type(type))
        # Lastly, "(unnamed ...)" struct and union are handled here, which are also struct-specific.
        in Node[kind: :field_decl, spelling:, children: [grandchild]]
          buf << field_builder.call(spelling, generate_node(grandchild).gsub(/^/, '  ').sub(/\A +/, ''))
        else # forward declarations are ignored
        end
      end
      buf << ")"
    when :typedef_decl
      case node.children
      in [child]
        generate_node(child)
      in [child, Node[kind: :integer_literal]]
        generate_node(child)
      in _ unless node.typedef_type.empty?
        generate_type(node.typedef_type)
      end
    when :enum_decl
      generate_type('int')
    when :type_ref
      generate_type(node.spelling)
    end
  end

  # Generate code from a type name. Used for resolving the name of a simple leaf node.
  # @param type [String]
  def generate_type(type)
    if type.match?(/\[\d+\]\z/)
      return "CType::Pointer.new { #{generate_type(type.sub!(/\[\d+\]\z/, ''))} }"
    end
    type = type.delete_suffix('const')
    if type.end_with?('*')
      return "CType::Pointer.new { #{generate_type(type.delete_suffix('*').rstrip)} }"
    end

    type = type.gsub(/((const|volatile) )+/, '').rstrip
    if type.start_with?(/(struct|union|enum) /)
      target = type.split(' ', 2).last
      push_target(target)
      "self.#{target}"
    else
      begin
        ctype = Fiddle::Importer.parse_ctype(type)
        "CType::Immediate.new(#{ctype})"
      rescue Fiddle::DLError
        push_target(type)
        "self.#{type}"
      end
    end
  end

  def print(str)
    @src << str
  end

  def println(str = "")
    @src << str << "\n"
  end

  def chomp
    @src.delete_suffix!("\n")
  end

  def rstrip!
    @src.rstrip!
  end

  def push_target(target)
    unless target.match?(/\A\w+\z/)
      raise "invalid target: #{target}"
    end
    @references << target
  end
end

src_dir = File.expand_path('../..', __dir__)
build_dir = File.expand_path(build_dir)
cflags = [
  src_dir,
  build_dir,
  File.join(src_dir, 'include'),
  File.join(build_dir, ".ext/include/#{RUBY_PLATFORM}"),
].map { |dir| "-I#{dir}" }

nodes = HeaderParser.new(File.join(src_dir, 'mjit_compiler.h'), cflags: cflags).parse
generator = BindingGenerator.new(
  macros: %w[
    NOT_COMPILED_STACK_SIZE
    USE_LAZY_LOAD
    USE_RVARGC
    VM_CALL_KW_SPLAT
    VM_CALL_TAILCALL
  ],
  enums: {
    rb_method_type_t: %w[
      VM_METHOD_TYPE_CFUNC
      VM_METHOD_TYPE_ISEQ
    ],
    vm_call_flag_bits: %w[
      VM_CALL_KW_SPLAT_bit
      VM_CALL_TAILCALL_bit
    ],
  },
  types: %w[
    CALL_DATA
    IC
    IVC
    RB_BUILTIN
    VALUE
    compile_branch
    compile_status
    inlined_call_context
    iseq_inline_constant_cache
    iseq_inline_constant_cache_entry
    iseq_inline_iv_cache_entry
    iseq_inline_storage_entry
    mjit_options
    rb_builtin_function
    rb_call_data
    rb_callable_method_entry_struct
    rb_callcache
    rb_callinfo
    rb_cref_t
    rb_control_frame_t
    rb_execution_context_t
    rb_execution_context_struct
    rb_iseq_constant_body
    rb_iseq_location_t
    rb_iseq_struct
    rb_iseq_t
    rb_iv_index_tbl_entry
    rb_method_definition_struct
    rb_method_iseq_t
    rb_method_type_t
    rb_mjit_compile_info
    rb_mjit_unit
    rb_serial_t
  ],
  ruby_fields: {
    rb_iseq_location_struct: %w[
      base_label
      first_lineno
      label
      pathobj
    ]
  },
)
generator.generate(nodes)

File.write(File.join(src_dir, "lib/mjit/c_#{arch_bits}.rb"), generator.src)
