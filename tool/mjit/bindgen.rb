#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['GEM_HOME'] = File.expand_path('./.bundle', __dir__)
require 'rubygems/source'
require 'bundler/inline'
gemfile(true) do
  source 'https://rubygems.org'
  gem 'ffi-clang', '0.7.0', require: false
end

# Help ffi-clang find libclang
# Hint: apt install libclang1
ENV['LIBCLANG'] ||= Dir.glob("/usr/lib/llvm-*/lib/libclang.so.1").grep_v(/-cpp/).sort.last
require 'ffi/clang'

require 'etc'
require 'fiddle/import'
require 'set'

unless build_dir = ARGV.first
  abort "Usage: #{$0} BUILD_DIR"
end

class Node < Struct.new(
  :kind,
  :spelling,
  :type,
  :typedef_type,
  :bitwidth,
  :sizeof_type,
  :offsetof,
  :enum_value,
  :children,
  keyword_init: true,
)
end

# Parse a C header with ffi-clang and return Node objects.
# To ease the maintenance, ffi-clang should be used only inside this class.
class HeaderParser
  def initialize(header, cflags:)
    @translation_unit = FFI::Clang::Index.new.parse_translation_unit(header, cflags, [], {})
  end

  def parse
    parse_children(@translation_unit.cursor)
  end

  private

  def parse_children(cursor)
    children = []
    cursor.visit_children do |cursor, _parent|
      children << parse_cursor(cursor)
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
      enum_value: enum_value,
      children: children,
    )
  end
end

# Convert Node objects to a Ruby binding source.
class BindingGenerator
  BINDGEN_BEG = '### MJIT bindgen begin ###'
  BINDGEN_END = '### MJIT bindgen end ###'
  DEFAULTS = { '_Bool' => 'CType::Bool.new' }
  DEFAULTS.default_proc = proc { |_h, k| "CType::Stub.new(:#{k})" }

  attr_reader :src

  # @param src_path [String]
  # @param uses [Array<String>]
  # @param values [Hash{ Symbol => Array<String> }]
  # @param types [Array<String>]
  # @param dynamic_types [Array<String>] #ifdef-dependent immediate types, which need Primitive.cexpr! for type detection
  # @param skip_fields [Hash{ Symbol => Array<String> }] Struct fields that are skipped from bindgen
  # @param ruby_fields [Hash{ Symbol => Array<String> }] Struct VALUE fields that are considered Ruby objects
  def initialize(src_path:, uses:, values:, types:, dynamic_types:, skip_fields:, ruby_fields:)
    @preamble, @postamble = split_ambles(src_path)
    @src = String.new
    @uses = uses.sort
    @values = values.transform_values(&:sort)
    @types = types.sort
    @dynamic_types = dynamic_types.sort
    @skip_fields = skip_fields.transform_keys(&:to_s)
    @ruby_fields = ruby_fields.transform_keys(&:to_s)
    @references = Set.new
  end

  def generate(nodes)
    println @preamble

    # Define USE_* macros
    @uses.each do |use|
      println "  def C.#{use}"
      println "    Primitive.cexpr! %q{ RBOOL(#{use} != 0) }"
      println "  end"
      println
    end

    # Define macros/enums
    @values.each do |type, values|
      values.each do |value|
        println "  def C.#{value}"
        println "    Primitive.cexpr! %q{ #{type}2NUM(#{value}) }"
        println "  end"
        println
      end
    end

    # TODO: Support nested declarations
    nodes_index = nodes.group_by(&:spelling).transform_values(&:last)

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

    # Define dynamic types
    @dynamic_types.each do |type|
      unless generate_node(nodes_index[type])&.start_with?('CType::Immediate')
        raise "Non-immediate type is given to dynamic_types: #{type}"
      end
      println "  def C.#{type}"
      println "    @#{type} ||= CType::Immediate.find(Primitive.cexpr!(\"SIZEOF(#{type})\"), Primitive.cexpr!(\"SIGNED_TYPE_P(#{type})\"))"
      println "  end"
      println
    end

    # Leave a stub for types that are referenced but not targeted
    (@references - @types - @dynamic_types).each do |type|
      println "  def C.#{type}"
      println "    #{DEFAULTS[type]}"
      println "  end"
      println
    end

    print @postamble
  end

  private

  # Return code before BINDGEN_BEG and code after BINDGEN_END
  def split_ambles(src_path)
    lines = File.read(src_path).lines

    preamble_end = lines.index { |l| l.include?(BINDGEN_BEG) }
    raise "`#{BINDGEN_BEG}` was not found in '#{src_path}'" if preamble_end.nil?

    postamble_beg = lines.index { |l| l.include?(BINDGEN_END) }
    raise "`#{BINDGEN_END}` was not found in '#{src_path}'" if postamble_beg.nil?
    raise "`#{BINDGEN_BEG}` was found after `#{BINDGEN_END}`" if preamble_end >= postamble_beg

    return lines[0..preamble_end].join, lines[postamble_beg..-1].join
  end

  # Generate code from a node. Used for constructing a complex nested node.
  # @param node [Node]
  def generate_node(node, sizeof_type: nil)
    case node&.kind
    when :struct, :union
      # node.spelling is often empty for union, but we'd like to give it a name when it has one.
      buf = +"CType::#{node.kind.to_s.sub(/\A[a-z]/, &:upcase)}.new(\n"
      buf << "  \"#{node.spelling}\", Primitive.cexpr!(\"SIZEOF(#{sizeof_type || node.type})\"),\n"
      bit_fields_end = node.children.index { |c| c.bitwidth == -1 } || node.children.size # first non-bit field index
      node.children.each_with_index do |child, i|
        skip_type = sizeof_type&.gsub(/\(\(struct ([^\)]+) \*\)NULL\)->/, '\1.') || node.spelling
        next if @skip_fields.fetch(skip_type, []).include?(child.spelling)
        field_builder = proc do |field, type|
          if node.kind == :struct
            to_ruby = @ruby_fields.fetch(node.spelling, []).include?(field)
            if child.bitwidth > 0
              if bit_fields_end <= i # give up offsetof calculation for non-leading bit fields
                raise "non-leading bit fields are not supported. consider including '#{field}' in skip_fields."
              end
              offsetof = node.offsetof.fetch(field)
            else
              off_type = sizeof_type || "(*((#{node.type} *)NULL))"
              offsetof = "Primitive.cexpr!(\"OFFSETOF(#{off_type}, #{field})\")"
            end
            "  #{field}: [#{type}, #{offsetof}#{', true' if to_ruby}],\n"
          else
            "  #{field}: #{type},\n"
          end
        end

        case child
        # BitField is struct-specific. So it must be handled here.
        in Node[kind: :field_decl, spelling:, bitwidth:, children: [_grandchild, *]] if bitwidth > 0
          buf << field_builder.call(spelling, "CType::BitField.new(#{bitwidth}, #{node.offsetof.fetch(spelling) % 8})")
        # "(unnamed ...)" struct and union are handled here, which are also struct-specific.
        in Node[kind: :field_decl, spelling:, type:, children: [grandchild]] if type.match?(/\((unnamed|anonymous) [^)]+\)\z/)
          if sizeof_type
            child_type = "#{sizeof_type}.#{child.spelling}"
          else
            child_type = "((#{node.type} *)NULL)->#{child.spelling}"
          end
          buf << field_builder.call(spelling, generate_node(grandchild, sizeof_type: child_type).gsub(/^/, '  ').sub(/\A +/, ''))
        # In most cases, we'd like to let generate_type handle the type unless it's "(unnamed ...)".
        in Node[kind: :field_decl, spelling:, type:] if !type.empty?
          buf << field_builder.call(spelling, generate_type(type))
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
      rescue Fiddle::DLError
        push_target(type)
        "self.#{type}"
      else
        # Convert any function pointers to void* to workaround FILE* vs int*
        if ctype == Fiddle::TYPE_VOIDP
          "CType::Immediate.parse(\"void *\")"
        else
          "CType::Immediate.parse(#{type.dump})"
        end
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
src_path = File.join(src_dir, 'mjit_c.rb')
build_dir = File.expand_path(build_dir)
cflags = [
  src_dir,
  build_dir,
  File.join(src_dir, 'include'),
  File.join(build_dir, ".ext/include/#{RUBY_PLATFORM}"),
].map { |dir| "-I#{dir}" }

# Clear .cache/clangd created by the language server, which could break this bindgen
clangd_cache = File.join(src_dir, '.cache/clangd')
if Dir.exist?(clangd_cache)
  system('rm', '-rf', clangd_cache, exception: true)
end

# Parse mjit_c.h and generate mjit_c.rb
nodes = HeaderParser.new(File.join(src_dir, 'mjit_c.h'), cflags: cflags).parse
generator = BindingGenerator.new(
  src_path: src_path,
  uses: %w[
    USE_LAZY_LOAD
  ],
  values: {
    INT: %w[
      NOT_COMPILED_STACK_SIZE
      VM_CALL_KW_SPLAT
      VM_CALL_KW_SPLAT_bit
      VM_CALL_TAILCALL
      VM_CALL_TAILCALL_bit
      VM_METHOD_TYPE_CFUNC
      VM_METHOD_TYPE_ISEQ
    ],
    UINT: %w[
      RUBY_EVENT_CLASS
      SHAPE_CAPACITY_CHANGE
      SHAPE_FLAG_SHIFT
      SHAPE_FROZEN
      SHAPE_ID_NUM_BITS
      SHAPE_INITIAL_CAPACITY
      SHAPE_IVAR
      SHAPE_ROOT
    ],
    ULONG: %w[
      INVALID_SHAPE_ID
      SHAPE_MASK
    ],
    PTR: %w[
      rb_cFalseClass
      rb_cFloat
      rb_cInteger
      rb_cNilClass
      rb_cSymbol
      rb_cTrueClass
    ],
  },
  types: %w[
    CALL_DATA
    IC
    IVC
    RB_BUILTIN
    attr_index_t
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
    rb_control_frame_t
    rb_cref_t
    rb_execution_context_struct
    rb_execution_context_t
    rb_iseq_constant_body
    rb_iseq_location_t
    rb_iseq_struct
    rb_iseq_t
    rb_method_definition_struct
    rb_method_iseq_t
    rb_method_type_t
    rb_mjit_compile_info
    rb_mjit_unit
    rb_serial_t
    rb_shape
    rb_shape_t
  ],
  dynamic_types: %w[
    VALUE
    shape_id_t
  ],
  skip_fields: {
    'rb_execution_context_struct.machine': %w[regs], # differs between macOS and Linux
    rb_execution_context_struct: %w[method_missing_reason], # non-leading bit fields not supported
    rb_iseq_constant_body: %w[yjit_payload], # conditionally defined
  },
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

# Write mjit_c.rb
File.write(src_path, generator.src)
