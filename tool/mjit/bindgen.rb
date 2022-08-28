#!/usr/bin/env ruby
# frozen_string_literal: true
require 'etc'
require 'fiddle/import'
require 'set'

arch_bits = Integer(ARGV.first || 64)

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
    println "  C = Object.new"
    println

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
        tokens.drop(1).map do |token|
          case token
          when /\A(0x)?\d+\z/, '(', '-', '<<',  ')'
            token
          when *@enums.values.flatten
            "self.#{token}"
          else
            raise "unexpected macro token: #{token}"
          end
        end.join(' ')
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
        in Node[kind: :field_decl, spelling:, type:] if !type.empty? && !type.match?(/\(unnamed [^)]+\)\z/)
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
if arch_bits == 64
  build_dir = File.join(src_dir, '.ruby')
  ruby_platform = RUBY_PLATFORM
else
  build_dir = File.join(src_dir, '.ruby-m32')
  ruby_platform = 'i686-linux'
end
cflags = [
  src_dir,
  build_dir,
  File.join(src_dir, 'include'),
  File.join(build_dir, ".ext/include/#{ruby_platform}"),
].map { |dir| "-I#{dir}" }

nodes = HeaderParser.new(File.join(src_dir, 'mjit_compiler.h'), cflags: cflags).parse
generator = BindingGenerator.new(
  macros: %w[
    USE_LAZY_LOAD
    USE_RVARGC
    VM_CALL_KW_SPLAT
    VM_CALL_TAILCALL
    NOT_COMPILED_STACK_SIZE
  ],
  enums: {
    rb_method_type_t: %w[
      VM_METHOD_TYPE_ISEQ
      VM_METHOD_TYPE_CFUNC
    ],
    vm_call_flag_bits: %w[
      VM_CALL_KW_SPLAT_bit
      VM_CALL_TAILCALL_bit
    ],
  },
  types: %w[
    IC
    IVC
    RB_BUILTIN
    VALUE
    compile_status
    iseq_inline_constant_cache
    iseq_inline_constant_cache_entry
    iseq_inline_iv_cache_entry
    iseq_inline_storage_entry
    rb_builtin_function
    rb_cref_t
    rb_iseq_constant_body
    rb_iseq_struct
    rb_iseq_t
    rb_iv_index_tbl_entry
    rb_mjit_compile_info
    rb_serial_t
    rb_mjit_unit
    CALL_DATA
    rb_call_data
    rb_callcache
    rb_callable_method_entry_struct
    rb_method_definition_struct
    rb_method_iseq_t
    rb_callinfo
    rb_method_type_t
    mjit_options
    compile_branch
    inlined_call_context
    rb_iseq_location_t
  ],
  ruby_fields: {
    rb_iseq_location_struct: %w[
      pathobj
      base_label
      label
      first_lineno
    ]
  },
)
generator.generate(nodes)

File.write(File.join(src_dir, "lib/mjit/c_#{arch_bits}.rb"), generator.src)
