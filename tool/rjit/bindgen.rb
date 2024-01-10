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
  BINDGEN_BEG = '### RJIT bindgen begin ###'
  BINDGEN_END = '### RJIT bindgen end ###'
  DEFAULTS = { '_Bool' => 'CType::Bool.new' }
  DEFAULTS.default_proc = proc { |_h, k| "CType::Stub.new(:#{k})" }

  attr_reader :src

  # @param src_path [String]
  # @param consts [Hash{ Symbol => Array<String> }]
  # @param values [Hash{ Symbol => Array<String> }]
  # @param funcs [Array<String>]
  # @param types [Array<String>]
  # @param dynamic_types [Array<String>] #ifdef-dependent immediate types, which need Primitive.cexpr! for type detection
  # @param skip_fields [Hash{ Symbol => Array<String> }] Struct fields that are skipped from bindgen
  # @param ruby_fields [Hash{ Symbol => Array<String> }] Struct VALUE fields that are considered Ruby objects
  def initialize(src_path:, consts:, values:, funcs:, types:, dynamic_types:, skip_fields:, ruby_fields:)
    @preamble, @postamble = split_ambles(src_path)
    @src = String.new
    @consts = consts.transform_values(&:sort)
    @values = values.transform_values(&:sort)
    @funcs = funcs.sort
    @types = types.sort
    @dynamic_types = dynamic_types.sort
    @skip_fields = skip_fields.transform_keys(&:to_s)
    @ruby_fields = ruby_fields.transform_keys(&:to_s)
    @references = Set.new
  end

  def generate(nodes)
    println @preamble

    # Define macros/enums
    @consts.each do |type, values|
      values.each do |value|
        raise "#{value} isn't a valid constant name" unless ('A'..'Z').include?(value[0])
        println "  C::#{value} = Primitive.cexpr! %q{ #{type}2NUM(#{value}) }"
      end
    end
    println

    # Define variables
    @values.each do |type, values|
      values.each do |value|
        println "  def C.#{value}"
        println "    Primitive.cexpr! %q{ #{type}2NUM(#{value}) }"
        println "  end"
        println
      end
    end

    # Define function pointers
    @funcs.each do |func|
      println "  def C.#{func}"
      println "    Primitive.cexpr! %q{ SIZET2NUM((size_t)#{func}) }"
      println "  end"
      println
    end

    # Build a hash table for type lookup by name
    nodes_index = flatten_nodes(nodes).group_by(&:spelling).transform_values do |values|
      # Try to search a declaration with definitions
      node_with_children = values.find { |v| !v.children.empty? }
      next node_with_children if node_with_children

      # Otherwise, assume the last one is the main declaration
      values.last
    end

    # Define types
    @types.each do |type|
      unless definition = generate_node(nodes_index[type])
        raise "Failed to find or generate type: #{type}"
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

  # Make an array that includes all top-level and nested nodes
  def flatten_nodes(nodes)
    result = []
    nodes.each do |node|
      unless node.children.empty?
        result.concat(flatten_nodes(node.children))
      end
    end
    result.concat(nodes) # prioritize top-level nodes
    result
  end

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
      return "CType::Array.new { #{generate_type(type.sub!(/\[\d+\]\z/, ''))} }"
    end
    type = type.delete_suffix('const')
    if type.end_with?('*')
      if type == 'const void *'
        # `CType::Pointer.new { CType::Immediate.parse("void") }` is never useful,
        # so specially handle that case here.
        return 'CType::Immediate.parse("void *")'
      end
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
src_path = File.join(src_dir, 'rjit_c.rb')
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

# Parse rjit_c.h and generate rjit_c.rb
nodes = HeaderParser.new(File.join(src_dir, 'rjit_c.h'), cflags: cflags).parse
generator = BindingGenerator.new(
  src_path: src_path,
  consts: {
    LONG: %w[
      UNLIMITED_ARGUMENTS
      VM_ENV_DATA_INDEX_ME_CREF
      VM_ENV_DATA_INDEX_SPECVAL
    ],
    SIZET: %w[
      ARRAY_REDEFINED_OP_FLAG
      BOP_AND
      BOP_AREF
      BOP_EQ
      BOP_EQQ
      BOP_FREEZE
      BOP_GE
      BOP_GT
      BOP_LE
      BOP_LT
      BOP_MINUS
      BOP_MOD
      BOP_OR
      BOP_PLUS
      BUILTIN_ATTR_LEAF
      BUILTIN_ATTR_NO_GC
      HASH_REDEFINED_OP_FLAG
      INTEGER_REDEFINED_OP_FLAG
      INVALID_SHAPE_ID
      METHOD_VISI_PRIVATE
      METHOD_VISI_PROTECTED
      METHOD_VISI_PUBLIC
      METHOD_VISI_UNDEF
      OBJ_TOO_COMPLEX_SHAPE_ID
      OPTIMIZED_METHOD_TYPE_BLOCK_CALL
      OPTIMIZED_METHOD_TYPE_CALL
      OPTIMIZED_METHOD_TYPE_SEND
      OPTIMIZED_METHOD_TYPE_STRUCT_AREF
      OPTIMIZED_METHOD_TYPE_STRUCT_ASET
      RARRAY_EMBED_FLAG
      RARRAY_EMBED_LEN_MASK
      RARRAY_EMBED_LEN_SHIFT
      RMODULE_IS_REFINEMENT
      ROBJECT_EMBED
      RSTRUCT_EMBED_LEN_MASK
      RUBY_EVENT_CLASS
      RUBY_EVENT_C_CALL
      RUBY_EVENT_C_RETURN
      RUBY_FIXNUM_FLAG
      RUBY_FLONUM_FLAG
      RUBY_FLONUM_MASK
      RUBY_FL_SINGLETON
      RUBY_IMMEDIATE_MASK
      RUBY_SPECIAL_SHIFT
      RUBY_SYMBOL_FLAG
      RUBY_T_ARRAY
      RUBY_T_CLASS
      RUBY_T_ICLASS
      RUBY_T_HASH
      RUBY_T_MASK
      RUBY_T_MODULE
      RUBY_T_STRING
      RUBY_T_SYMBOL
      RUBY_T_OBJECT
      SHAPE_FLAG_SHIFT
      SHAPE_FROZEN
      SHAPE_ID_NUM_BITS
      SHAPE_IVAR
      SHAPE_MASK
      SHAPE_ROOT
      STRING_REDEFINED_OP_FLAG
      T_OBJECT
      VM_BLOCK_HANDLER_NONE
      VM_CALL_ARGS_BLOCKARG
      VM_CALL_ARGS_SPLAT
      VM_CALL_FCALL
      VM_CALL_KWARG
      VM_CALL_KW_SPLAT
      VM_CALL_KW_SPLAT_MUT
      VM_CALL_KW_SPLAT_bit
      VM_CALL_OPT_SEND
      VM_CALL_TAILCALL
      VM_CALL_TAILCALL_bit
      VM_CALL_ZSUPER
      VM_ENV_DATA_INDEX_FLAGS
      VM_ENV_DATA_SIZE
      VM_ENV_FLAG_LOCAL
      VM_ENV_FLAG_WB_REQUIRED
      VM_FRAME_FLAG_BMETHOD
      VM_FRAME_FLAG_CFRAME
      VM_FRAME_FLAG_CFRAME_KW
      VM_FRAME_FLAG_LAMBDA
      VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM
      VM_FRAME_MAGIC_BLOCK
      VM_FRAME_MAGIC_CFUNC
      VM_FRAME_MAGIC_METHOD
      VM_METHOD_TYPE_ALIAS
      VM_METHOD_TYPE_ATTRSET
      VM_METHOD_TYPE_BMETHOD
      VM_METHOD_TYPE_CFUNC
      VM_METHOD_TYPE_ISEQ
      VM_METHOD_TYPE_IVAR
      VM_METHOD_TYPE_MISSING
      VM_METHOD_TYPE_NOTIMPLEMENTED
      VM_METHOD_TYPE_OPTIMIZED
      VM_METHOD_TYPE_REFINED
      VM_METHOD_TYPE_UNDEF
      VM_METHOD_TYPE_ZSUPER
      VM_SPECIAL_OBJECT_VMCORE
      RUBY_ENCODING_MASK
      RUBY_FL_FREEZE
      RHASH_PASS_AS_KEYWORDS
    ],
  },
  values: {
    SIZET: %w[
      block_type_iseq
      imemo_iseq
      imemo_callinfo
      rb_block_param_proxy
      rb_cArray
      rb_cFalseClass
      rb_cFloat
      rb_cInteger
      rb_cNilClass
      rb_cString
      rb_cSymbol
      rb_cTrueClass
      rb_rjit_global_events
      rb_mRubyVMFrozenCore
      rb_vm_insns_count
      idRespond_to_missing
    ],
  },
  funcs: %w[
    rb_ary_entry_internal
    rb_ary_push
    rb_ary_resurrect
    rb_ary_store
    rb_ec_ary_new_from_values
    rb_ec_str_resurrect
    rb_ensure_iv_list_size
    rb_fix_aref
    rb_fix_div_fix
    rb_fix_mod_fix
    rb_fix_mul_fix
    rb_gc_writebarrier
    rb_get_symbol_id
    rb_hash_aref
    rb_hash_aset
    rb_hash_bulk_insert
    rb_hash_new
    rb_hash_new_with_size
    rb_hash_resurrect
    rb_ivar_get
    rb_obj_as_string_result
    rb_obj_is_kind_of
    rb_str_concat_literals
    rb_str_eql_internal
    rb_str_getbyte
    rb_vm_bh_to_procval
    rb_vm_concat_array
    rb_vm_defined
    rb_vm_get_ev_const
    rb_vm_getclassvariable
    rb_vm_ic_hit_p
    rb_vm_opt_newarray_min
    rb_vm_opt_newarray_max
    rb_vm_opt_newarray_hash
    rb_vm_setinstancevariable
    rb_vm_splat_array
    rjit_full_cfunc_return
    rjit_optimized_call
    rjit_str_neq_internal
    rjit_record_exit_stack
    rb_ivar_defined
    rb_vm_throw
    rb_backref_get
    rb_reg_last_match
    rb_reg_match_pre
    rb_reg_match_post
    rb_reg_match_last
    rb_reg_nth_match
    rb_gvar_get
    rb_range_new
    rb_ary_tmp_new_from_values
    rb_reg_new_ary
    rb_ary_clear
    rb_str_intern
    rb_vm_setclassvariable
    rb_str_bytesize
    rjit_str_simple_append
    rb_str_buf_append
    rb_str_dup
    rb_vm_yield_with_cfunc
    rb_vm_set_ivar_id
    rb_ary_dup
    rjit_rb_ary_subseq_length
    rb_ary_unshift_m
    rjit_build_kwhash
    rb_rjit_entry_stub_hit
    rb_rjit_branch_stub_hit
    rb_sym_to_proc
  ],
  types: %w[
    CALL_DATA
    IC
    ID
    IVC
    RArray
    RB_BUILTIN
    RBasic
    RObject
    RStruct
    RString
    attr_index_t
    iseq_inline_constant_cache
    iseq_inline_constant_cache_entry
    iseq_inline_iv_cache_entry
    iseq_inline_storage_entry
    method_optimized_type
    rb_block
    rb_block_type
    rb_builtin_function
    rb_call_data
    rb_callable_method_entry_struct
    rb_callable_method_entry_t
    rb_callcache
    rb_callinfo
    rb_captured_block
    rb_control_frame_t
    rb_cref_t
    rb_execution_context_struct
    rb_execution_context_t
    rb_iseq_constant_body
    rb_iseq_location_t
    rb_iseq_struct
    rb_iseq_t
    rb_method_attr_t
    rb_method_bmethod_t
    rb_method_cfunc_t
    rb_method_definition_struct
    rb_method_entry_t
    rb_method_iseq_t
    rb_method_optimized_t
    rb_method_type_t
    rb_proc_t
    rb_rjit_runtime_counters
    rb_serial_t
    rb_shape
    rb_shape_t
    rb_thread_struct
    rb_jit_func_t
    rb_iseq_param_keyword
    rb_rjit_options
    rb_callinfo_kwarg
  ],
  # #ifdef-dependent immediate types, which need Primitive.cexpr! for type detection
  dynamic_types: %w[
    VALUE
    shape_id_t
  ],
  skip_fields: {
    'rb_execution_context_struct.machine': %w[regs], # differs between macOS and Linux
    rb_execution_context_struct: %w[method_missing_reason], # non-leading bit fields not supported
    rb_iseq_constant_body: %w[jit_exception jit_exception_calls yjit_payload yjit_calls_at_interv], # conditionally defined
    rb_thread_struct: %w[status has_dedicated_nt to_kill abort_on_exception report_on_exception pending_interrupt_queue_checked],
    :'' => %w[is_from_method is_lambda is_isolated], # rb_proc_t
  },
  ruby_fields: {
    rb_iseq_constant_body: %w[
      rjit_blocks
    ],
    rb_iseq_location_struct: %w[
      base_label
      label
      pathobj
    ],
    rb_callable_method_entry_t: %w[
      defined_class
    ],
    rb_callable_method_entry_struct: %w[
      defined_class
    ],
  },
)
generator.generate(nodes)

# Write rjit_c.rb
File.write(src_path, generator.src)
