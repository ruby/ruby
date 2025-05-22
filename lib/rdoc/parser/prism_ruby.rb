# frozen_string_literal: true

require 'prism'
require_relative 'ripper_state_lex'

# Unlike lib/rdoc/parser/ruby.rb, this file is not based on rtags and does not contain code from
#   rtags.rb -
#   ruby-lex.rb - ruby lexcal analyzer
#   ruby-token.rb - ruby tokens

# Parse and collect document from Ruby source code.
# RDoc::Parser::PrismRuby is compatible with RDoc::Parser::Ruby and aims to replace it.

class RDoc::Parser::PrismRuby < RDoc::Parser

  parse_files_matching(/\.rbw?$/) if ENV['RDOC_USE_PRISM_PARSER']

  attr_accessor :visibility
  attr_reader :container, :singleton

  def initialize(top_level, content, options, stats)
    super

    content = handle_tab_width(content)

    @size = 0
    @token_listeners = nil
    content = RDoc::Encoding.remove_magic_comment content
    @content = content
    @markup = @options.markup
    @track_visibility = :nodoc != @options.visibility
    @encoding = @options.encoding

    @module_nesting = [[top_level, false]]
    @container = top_level
    @visibility = :public
    @singleton = false
    @in_proc_block = false
  end

  # Suppress `extend` and `include` within block
  # because they might be a metaprogramming block
  # example: `Module.new { include M }` `M.module_eval { include N }`

  def with_in_proc_block
    @in_proc_block = true
    yield
    @in_proc_block = false
  end

  # Dive into another container

  def with_container(container, singleton: false)
    old_container = @container
    old_visibility = @visibility
    old_singleton = @singleton
    old_in_proc_block = @in_proc_block
    @visibility = :public
    @container = container
    @singleton = singleton
    @in_proc_block = false
    unless singleton
      # Need to update module parent chain to emulate Module.nesting.
      # This mechanism is inaccurate and needs to be fixed.
      container.parent = old_container
    end
    @module_nesting.push([container, singleton])
    yield container
  ensure
    @container = old_container
    @visibility = old_visibility
    @singleton = old_singleton
    @in_proc_block = old_in_proc_block
    @module_nesting.pop
  end

  # Records the location of this +container+ in the file for this parser and
  # adds it to the list of classes and modules in the file.

  def record_location(container) # :nodoc:
    case container
    when RDoc::ClassModule then
      @top_level.add_to_classes_or_modules container
    end

    container.record_location @top_level
  end

  # Scans this Ruby file for Ruby constructs

  def scan
    @tokens = RDoc::Parser::RipperStateLex.parse(@content)
    @lines = @content.lines
    result = Prism.parse(@content)
    @program_node = result.value
    @line_nodes = {}
    prepare_line_nodes(@program_node)
    prepare_comments(result.comments)
    return if @top_level.done_documenting

    @first_non_meta_comment = nil
    if (_line_no, start_line, rdoc_comment = @unprocessed_comments.first)
      @first_non_meta_comment = rdoc_comment if start_line < @program_node.location.start_line
    end

    @program_node.accept(RDocVisitor.new(self, @top_level, @store))
    process_comments_until(@lines.size + 1)
  end

  def should_document?(code_object) # :nodoc:
    return true unless @track_visibility
    return false if code_object.parent&.document_children == false
    code_object.document_self
  end

  # Assign AST node to a line.
  # This is used to show meta-method source code in the documentation.

  def prepare_line_nodes(node) # :nodoc:
    case node
    when Prism::CallNode, Prism::DefNode
      @line_nodes[node.location.start_line] ||= node
    end
    node.compact_child_nodes.each do |child|
      prepare_line_nodes(child)
    end
  end

  # Prepares comments for processing. Comments are grouped into consecutive.
  # Consecutive comment is linked to the next non-blank line.
  #
  # Example:
  #   01| class A # modifier comment 1
  #   02|   def foo; end # modifier comment 2
  #   03|
  #   04|   # consecutive comment 1 start_line: 4
  #   05|   # consecutive comment 1 linked to line: 7
  #   06|
  #   07|   # consecutive comment 2 start_line: 7
  #   08|   # consecutive comment 2 linked to line: 10
  #   09|
  #   10|   def bar; end # consecutive comment 2 linked to this line
  #   11| end

  def prepare_comments(comments)
    current = []
    consecutive_comments = [current]
    @modifier_comments = {}
    comments.each do |comment|
      if comment.is_a? Prism::EmbDocComment
        consecutive_comments << [comment] << (current = [])
      elsif comment.location.start_line_slice.match?(/\S/)
        @modifier_comments[comment.location.start_line] = RDoc::Comment.new(comment.slice, @top_level, :ruby)
      elsif current.empty? || current.last.location.end_line + 1 == comment.location.start_line
        current << comment
      else
        consecutive_comments << (current = [comment])
      end
    end
    consecutive_comments.reject!(&:empty?)

    # Example: line_no = 5, start_line = 2, comment_text = "# comment_start_line\n# comment\n"
    # 1| class A
    # 2|   # comment_start_line
    # 3|   # comment
    # 4|
    # 5|   def f; end # comment linked to this line
    # 6| end
    @unprocessed_comments = consecutive_comments.map! do |comments|
      start_line = comments.first.location.start_line
      line_no = comments.last.location.end_line + (comments.last.location.end_column == 0 ? 0 : 1)
      texts = comments.map do |c|
        c.is_a?(Prism::EmbDocComment) ? c.slice.lines[1...-1].join : c.slice
      end
      text = RDoc::Encoding.change_encoding(texts.join("\n"), @encoding) if @encoding
      line_no += 1 while @lines[line_no - 1]&.match?(/\A\s*$/)
      comment = RDoc::Comment.new(text, @top_level, :ruby)
      comment.line = start_line
      [line_no, start_line, comment]
    end

    # The first comment is special. It defines markup for the rest of the comments.
    _, first_comment_start_line, first_comment_text = @unprocessed_comments.first
    if first_comment_text && @lines[0...first_comment_start_line - 1].all? { |l| l.match?(/\A\s*$/) }
      comment = RDoc::Comment.new(first_comment_text.text, @top_level, :ruby)
      handle_consecutive_comment_directive(@container, comment)
      @markup = comment.format
    end
    @unprocessed_comments.each do |_, _, comment|
      comment.format = @markup
    end
  end

  # Creates an RDoc::Method on +container+ from +comment+ if there is a
  # Signature section in the comment

  def parse_comment_tomdoc(container, comment, line_no, start_line)
    return unless signature = RDoc::TomDoc.signature(comment)

    name, = signature.split %r%[ \(]%, 2

    meth = RDoc::GhostMethod.new comment.text, name
    record_location(meth)
    meth.line = start_line
    meth.call_seq = signature
    return unless meth.name

    meth.start_collecting_tokens
    node = @line_nodes[line_no]
    tokens = node ? visible_tokens_from_location(node.location) : [file_line_comment_token(start_line)]
    tokens.each { |token| meth.token_stream << token }

    container.add_method meth
    comment.remove_private
    comment.normalize
    meth.comment = comment
    @stats.add_method meth
  end

  def has_modifier_nodoc?(line_no) # :nodoc:
    @modifier_comments[line_no]&.text&.match?(/\A#\s*:nodoc:/)
  end

  def handle_modifier_directive(code_object, line_no) # :nodoc:
    comment = @modifier_comments[line_no]
    @preprocess.handle(comment.text, code_object) if comment
  end

  def handle_consecutive_comment_directive(code_object, comment) # :nodoc:
    return unless comment
    @preprocess.handle(comment, code_object) do |directive, param|
      case directive
      when 'method', 'singleton-method',
           'attr', 'attr_accessor', 'attr_reader', 'attr_writer' then
        # handled elsewhere
        ''
      when 'section' then
        @container.set_current_section(param, comment.dup)
        comment.text = ''
        break
      end
    end
    comment.remove_private
  end

  def call_node_name_arguments(call_node) # :nodoc:
    return [] unless call_node.arguments
    call_node.arguments.arguments.map do |arg|
      case arg
      when Prism::SymbolNode
        arg.value
      when Prism::StringNode
        arg.unescaped
      end
    end || []
  end

  # Handles meta method comments

  def handle_meta_method_comment(comment, node)
    is_call_node = node.is_a?(Prism::CallNode)
    singleton_method = false
    visibility = @visibility
    attributes = rw = line_no = method_name = nil

    processed_comment = comment.dup
    @preprocess.handle(processed_comment, @container) do |directive, param, line|
      case directive
      when 'attr', 'attr_reader', 'attr_writer', 'attr_accessor'
        attributes = [param] if param
        attributes ||= call_node_name_arguments(node) if is_call_node
        rw = directive == 'attr_writer' ? 'W' : directive == 'attr_accessor' ? 'RW' : 'R'
        ''
      when 'method'
        method_name = param
        line_no = line
        ''
      when 'singleton-method'
        method_name = param
        line_no = line
        singleton_method = true
        visibility = :public
        ''
      when 'section' then
        @container.set_current_section(param, comment.dup)
        return # If the comment contains :section:, it is not a meta method comment
      end
    end

    if attributes
      attributes.each do |attr|
        a = RDoc::Attr.new(@container, attr, rw, processed_comment, singleton: @singleton)
        a.store = @store
        a.line = line_no
        record_location(a)
        @container.add_attribute(a)
        a.visibility = visibility
      end
    elsif line_no || node
      method_name ||= call_node_name_arguments(node).first if is_call_node
      meth = RDoc::AnyMethod.new(@container, method_name, singleton: @singleton || singleton_method)
      handle_consecutive_comment_directive(meth, comment)
      comment.normalize
      meth.call_seq = comment.extract_call_seq
      meth.comment = comment
      if node
        tokens = visible_tokens_from_location(node.location)
        line_no = node.location.start_line
      else
        tokens = [file_line_comment_token(line_no)]
      end
      internal_add_method(
        @container,
        meth,
        line_no: line_no,
        visibility: visibility,
        params: '()',
        calls_super: false,
        block_params: nil,
        tokens: tokens
      )
    end
  end

  def normal_comment_treat_as_ghost_method_for_now?(comment_text, line_no) # :nodoc:
    # Meta method comment should start with `##` but some comments does not follow this rule.
    # For now, RDoc accepts them as a meta method comment if there is no node linked to it.
    !@line_nodes[line_no] && comment_text.match?(/^#\s+:(method|singleton-method|attr|attr_reader|attr_writer|attr_accessor):/)
  end

  def handle_standalone_consecutive_comment_directive(comment, line_no, start_line) # :nodoc:
    if @markup == 'tomdoc'
      parse_comment_tomdoc(@container, comment, line_no, start_line)
      return
    end

    if comment.text =~ /\A#\#$/ && comment != @first_non_meta_comment
      node = @line_nodes[line_no]
      handle_meta_method_comment(comment, node)
    elsif normal_comment_treat_as_ghost_method_for_now?(comment.text, line_no) && comment != @first_non_meta_comment
      handle_meta_method_comment(comment, nil)
    else
      handle_consecutive_comment_directive(@container, comment)
    end
  end

  # Processes consecutive comments that were not linked to any documentable code until the given line number

  def process_comments_until(line_no_until)
    while !@unprocessed_comments.empty? && @unprocessed_comments.first[0] <= line_no_until
      line_no, start_line, rdoc_comment = @unprocessed_comments.shift
      handle_standalone_consecutive_comment_directive(rdoc_comment, line_no, start_line)
    end
  end

  # Skips all undocumentable consecutive comments until the given line number.
  # Undocumentable comments are comments written inside `def` or inside undocumentable class/module

  def skip_comments_until(line_no_until)
    while !@unprocessed_comments.empty? && @unprocessed_comments.first[0] <= line_no_until
      @unprocessed_comments.shift
    end
  end

  # Returns consecutive comment linked to the given line number

  def consecutive_comment(line_no)
    if @unprocessed_comments.first&.first == line_no
      @unprocessed_comments.shift.last
    end
  end

  def slice_tokens(start_pos, end_pos) # :nodoc:
    start_index = @tokens.bsearch_index { |t| ([t.line_no, t.char_no] <=> start_pos) >= 0 }
    end_index = @tokens.bsearch_index { |t| ([t.line_no, t.char_no] <=> end_pos) >= 0 }
    tokens = @tokens[start_index...end_index]
    tokens.pop if tokens.last&.kind == :on_nl
    tokens
  end

  def file_line_comment_token(line_no) # :nodoc:
    position_comment = RDoc::Parser::RipperStateLex::Token.new(line_no - 1, 0, :on_comment)
    position_comment[:text] = "# File #{@top_level.relative_name}, line #{line_no}"
    position_comment
  end

  # Returns tokens from the given location

  def visible_tokens_from_location(location)
    position_comment = file_line_comment_token(location.start_line)
    newline_token = RDoc::Parser::RipperStateLex::Token.new(0, 0, :on_nl, "\n")
    indent_token = RDoc::Parser::RipperStateLex::Token.new(location.start_line, 0, :on_sp, ' ' * location.start_character_column)
    tokens = slice_tokens(
      [location.start_line, location.start_character_column],
      [location.end_line, location.end_character_column]
    )
    [position_comment, newline_token, indent_token, *tokens]
  end

  # Handles `public :foo, :bar` `private :foo, :bar` and `protected :foo, :bar`

  def change_method_visibility(names, visibility, singleton: @singleton)
    new_methods = []
    @container.methods_matching(names, singleton) do |m|
      if m.parent != @container
        m = m.dup
        record_location(m)
        new_methods << m
      else
        m.visibility = visibility
      end
    end
    new_methods.each do |method|
      case method
      when RDoc::AnyMethod then
        @container.add_method(method)
      when RDoc::Attr then
        @container.add_attribute(method)
      end
      method.visibility = visibility
    end
  end

  # Handles `module_function :foo, :bar`

  def change_method_to_module_function(names)
    @container.set_visibility_for(names, :private, false)
    new_methods = []
    @container.methods_matching(names) do |m|
      s_m = m.dup
      record_location(s_m)
      s_m.singleton = true
      new_methods << s_m
    end
    new_methods.each do |method|
      case method
      when RDoc::AnyMethod then
        @container.add_method(method)
      when RDoc::Attr then
        @container.add_attribute(method)
      end
      method.visibility = :public
    end
  end

  # Handles `alias foo bar` and `alias_method :foo, :bar`

  def add_alias_method(old_name, new_name, line_no)
    comment = consecutive_comment(line_no)
    handle_consecutive_comment_directive(@container, comment)
    visibility = @container.find_method(old_name, @singleton)&.visibility || :public
    a = RDoc::Alias.new(nil, old_name, new_name, comment, singleton: @singleton)
    handle_modifier_directive(a, line_no)
    a.store = @store
    a.line = line_no
    record_location(a)
    if should_document?(a)
      @container.add_alias(a)
      @container.find_method(new_name, @singleton)&.visibility = visibility
    end
  end

  # Handles `attr :a, :b`, `attr_reader :a, :b`, `attr_writer :a, :b` and `attr_accessor :a, :b`

  def add_attributes(names, rw, line_no)
    comment = consecutive_comment(line_no)
    handle_consecutive_comment_directive(@container, comment)
    return unless @container.document_children

    names.each do |symbol|
      a = RDoc::Attr.new(nil, symbol.to_s, rw, comment, singleton: @singleton)
      a.store = @store
      a.line = line_no
      record_location(a)
      handle_modifier_directive(a, line_no)
      @container.add_attribute(a) if should_document?(a)
      a.visibility = visibility # should set after adding to container
    end
  end

  def add_includes_extends(names, rdoc_class, line_no) # :nodoc:
    return if @in_proc_block
    comment = consecutive_comment(line_no)
    handle_consecutive_comment_directive(@container, comment)
    names.each do |name|
      ie = @container.add(rdoc_class, name, '')
      ie.store = @store
      ie.line = line_no
      ie.comment = comment
      record_location(ie)
    end
  end

  # Handle `include Foo, Bar`

  def add_includes(names, line_no) # :nodoc:
    add_includes_extends(names, RDoc::Include, line_no)
  end

  # Handle `extend Foo, Bar`

  def add_extends(names, line_no) # :nodoc:
    add_includes_extends(names, RDoc::Extend, line_no)
  end

  # Adds a method defined by `def` syntax

  def add_method(name, receiver_name:, receiver_fallback_type:, visibility:, singleton:, params:, calls_super:, block_params:, tokens:, start_line:, args_end_line:, end_line:)
    return if @in_proc_block

    receiver = receiver_name ? find_or_create_module_path(receiver_name, receiver_fallback_type) : @container
    meth = RDoc::AnyMethod.new(nil, name, singleton: singleton)
    if (comment = consecutive_comment(start_line))
      handle_consecutive_comment_directive(@container, comment)
      handle_consecutive_comment_directive(meth, comment)

      comment.normalize
      meth.call_seq = comment.extract_call_seq
      meth.comment = comment
    end
    handle_modifier_directive(meth, start_line)
    handle_modifier_directive(meth, args_end_line)
    handle_modifier_directive(meth, end_line)
    return unless should_document?(meth)

    internal_add_method(
      receiver,
      meth,
      line_no: start_line,
      visibility: visibility,
      params: params,
      calls_super: calls_super,
      block_params: block_params,
      tokens: tokens
    )

    # Rename after add_method to register duplicated 'new' and 'initialize'
    # defined in c and ruby just like the old parser did.
    if meth.name == 'initialize' && !singleton
      if meth.dont_rename_initialize
        meth.visibility = :protected
      else
        meth.name = 'new'
        meth.singleton = true
        meth.visibility = :public
      end
    end
  end

  private def internal_add_method(container, meth, line_no:, visibility:, params:, calls_super:, block_params:, tokens:) # :nodoc:
    meth.name ||= meth.call_seq[/\A[^()\s]+/] if meth.call_seq
    meth.name ||= 'unknown'
    meth.store = @store
    meth.line = line_no
    container.add_method(meth) # should add after setting singleton and before setting visibility
    meth.visibility = visibility
    meth.params ||= params
    meth.calls_super = calls_super
    meth.block_params ||= block_params if block_params
    record_location(meth)
    meth.start_collecting_tokens
    tokens.each do |token|
      meth.token_stream << token
    end
  end

  # Find or create module or class from a given module name.
  # If module or class does not exist, creates a module or a class according to `create_mode` argument.

  def find_or_create_module_path(module_name, create_mode)
    root_name, *path, name = module_name.split('::')
    add_module = ->(mod, name, mode) {
      case mode
      when :class
        mod.add_class(RDoc::NormalClass, name, 'Object').tap { |m| m.store = @store }
      when :module
        mod.add_module(RDoc::NormalModule, name).tap { |m| m.store = @store }
      end
    }
    if root_name.empty?
      mod = @top_level
    else
      @module_nesting.reverse_each do |nesting, singleton|
        next if singleton
        mod = nesting.find_module_named(root_name)
        break if mod
        # If a constant is found and it is not a module or class, RDoc can't document about it.
        # Return an anonymous module to avoid wrong document creation.
        return RDoc::NormalModule.new(nil) if nesting.find_constant_named(root_name)
      end
      last_nesting, = @module_nesting.reverse_each.find { |_, singleton| !singleton }
      return mod || add_module.call(last_nesting, root_name, create_mode) unless name
      mod ||= add_module.call(last_nesting, root_name, :module)
    end
    path.each do |name|
      mod = mod.find_module_named(name) || add_module.call(mod, name, :module)
    end
    mod.find_module_named(name) || add_module.call(mod, name, create_mode)
  end

  # Resolves constant path to a full path by searching module nesting

  def resolve_constant_path(constant_path)
    owner_name, path = constant_path.split('::', 2)
    return constant_path if owner_name.empty? # ::Foo, ::Foo::Bar
    mod = nil
    @module_nesting.reverse_each do |nesting, singleton|
      next if singleton
      mod = nesting.find_module_named(owner_name)
      break if mod
    end
    mod ||= @top_level.find_module_named(owner_name)
    [mod.full_name, path].compact.join('::') if mod
  end

  # Returns a pair of owner module and constant name from a given constant path.
  # Creates owner module if it does not exist.

  def find_or_create_constant_owner_name(constant_path)
    const_path, colon, name = constant_path.rpartition('::')
    if colon.empty? # class Foo
      # Within `class C` or `module C`, owner is C(== current container)
      # Within `class <<C`, owner is C.singleton_class
      # but RDoc don't track constants of a singleton class of module
      [(@singleton ? nil : @container), name]
    elsif const_path.empty? # class ::Foo
      [@top_level, name]
    else # `class Foo::Bar` or `class ::Foo::Bar`
      [find_or_create_module_path(const_path, :module), name]
    end
  end

  # Adds a constant

  def add_constant(constant_name, rhs_name, start_line, end_line)
    comment = consecutive_comment(start_line)
    handle_consecutive_comment_directive(@container, comment)
    owner, name = find_or_create_constant_owner_name(constant_name)
    return unless owner

    constant = RDoc::Constant.new(name, rhs_name, comment)
    constant.store = @store
    constant.line = start_line
    record_location(constant)
    handle_modifier_directive(constant, start_line)
    handle_modifier_directive(constant, end_line)
    owner.add_constant(constant)
    mod =
      if rhs_name =~ /^::/
        @store.find_class_or_module(rhs_name)
      else
        @container.find_module_named(rhs_name)
      end
    if mod && constant.document_self
      a = @container.add_module_alias(mod, rhs_name, constant, @top_level)
      a.store = @store
      a.line = start_line
      record_location(a)
    end
  end

  # Adds module or class

  def add_module_or_class(module_name, start_line, end_line, is_class: false, superclass_name: nil, superclass_expr: nil)
    comment = consecutive_comment(start_line)
    handle_consecutive_comment_directive(@container, comment)
    return unless @container.document_children

    owner, name = find_or_create_constant_owner_name(module_name)
    return unless owner

    if is_class
      # RDoc::NormalClass resolves superclass name despite of the lack of module nesting information.
      # We need to fix it when RDoc::NormalClass resolved to a wrong constant name
      if superclass_name
        superclass_full_path = resolve_constant_path(superclass_name)
        superclass = @store.find_class_or_module(superclass_full_path) if superclass_full_path
        superclass_full_path ||= superclass_name
        superclass_full_path = superclass_full_path.sub(/^::/, '')
      end
      # add_class should be done after resolving superclass
      mod = owner.classes_hash[name] || owner.add_class(RDoc::NormalClass, name, superclass_name || superclass_expr || '::Object')
      if superclass_name
        if superclass
          mod.superclass = superclass
        elsif (mod.superclass.is_a?(String) || mod.superclass.name == 'Object') && mod.superclass != superclass_full_path
          mod.superclass = superclass_full_path
        end
      end
    else
      mod = owner.modules_hash[name] || owner.add_module(RDoc::NormalModule, name)
    end

    mod.store = @store
    mod.line = start_line
    record_location(mod)
    handle_modifier_directive(mod, start_line)
    handle_modifier_directive(mod, end_line)
    mod.add_comment(comment, @top_level) if comment
    mod
  end

  class RDocVisitor < Prism::Visitor # :nodoc:
    def initialize(scanner, top_level, store)
      @scanner = scanner
      @top_level = top_level
      @store = store
    end

    def visit_if_node(node)
      if node.end_keyword
        super
      else
        # Visit with the order in text representation to handle this method comment
        # # comment
        # def f
        # end if call_node
        node.statements.accept(self)
        node.predicate.accept(self)
      end
    end
    alias visit_unless_node visit_if_node

    def visit_call_node(node)
      @scanner.process_comments_until(node.location.start_line - 1)
      if node.receiver.nil?
        case node.name
        when :attr
          _visit_call_attr_reader_writer_accessor(node, 'R')
        when :attr_reader
          _visit_call_attr_reader_writer_accessor(node, 'R')
        when :attr_writer
          _visit_call_attr_reader_writer_accessor(node, 'W')
        when :attr_accessor
          _visit_call_attr_reader_writer_accessor(node, 'RW')
        when :include
          _visit_call_include(node)
        when :extend
          _visit_call_extend(node)
        when :public
          _visit_call_public_private_protected(node, :public) { super }
        when :private
          _visit_call_public_private_protected(node, :private) { super }
        when :protected
          _visit_call_public_private_protected(node, :protected) { super }
        when :private_constant
          _visit_call_private_constant(node)
        when :public_constant
          _visit_call_public_constant(node)
        when :require
          _visit_call_require(node)
        when :alias_method
          _visit_call_alias_method(node)
        when :module_function
          _visit_call_module_function(node) { super }
        when :public_class_method
          _visit_call_public_private_class_method(node, :public) { super }
        when :private_class_method
          _visit_call_public_private_class_method(node, :private) { super }
        else
          node.arguments&.accept(self)
          super
        end
      else
        super
      end
    end

    def visit_block_node(node)
      @scanner.with_in_proc_block do
        # include, extend and method definition inside block are not documentable
        super
      end
    end

    def visit_alias_method_node(node)
      @scanner.process_comments_until(node.location.start_line - 1)
      return unless node.old_name.is_a?(Prism::SymbolNode) && node.new_name.is_a?(Prism::SymbolNode)
      @scanner.add_alias_method(node.old_name.value.to_s, node.new_name.value.to_s, node.location.start_line)
    end

    def visit_module_node(node)
      node.constant_path.accept(self)
      @scanner.process_comments_until(node.location.start_line - 1)
      module_name = constant_path_string(node.constant_path)
      mod = @scanner.add_module_or_class(module_name, node.location.start_line, node.location.end_line) if module_name
      if mod
        @scanner.with_container(mod) do
          node.body&.accept(self)
          @scanner.process_comments_until(node.location.end_line)
        end
      else
        @scanner.skip_comments_until(node.location.end_line)
      end
    end

    def visit_class_node(node)
      node.constant_path.accept(self)
      node.superclass&.accept(self)
      @scanner.process_comments_until(node.location.start_line - 1)
      superclass_name = constant_path_string(node.superclass) if node.superclass
      superclass_expr = node.superclass.slice if node.superclass && !superclass_name
      class_name = constant_path_string(node.constant_path)
      klass = @scanner.add_module_or_class(class_name, node.location.start_line, node.location.end_line, is_class: true, superclass_name: superclass_name, superclass_expr: superclass_expr) if class_name
      if klass
        @scanner.with_container(klass) do
          node.body&.accept(self)
          @scanner.process_comments_until(node.location.end_line)
        end
      else
        @scanner.skip_comments_until(node.location.end_line)
      end
    end

    def visit_singleton_class_node(node)
      @scanner.process_comments_until(node.location.start_line - 1)

      if @scanner.has_modifier_nodoc?(node.location.start_line)
        # Skip visiting inside the singleton class. Also skips creation of node.expression as a module
        @scanner.skip_comments_until(node.location.end_line)
        return
      end

      expression = node.expression
      expression = expression.body.body.first if expression.is_a?(Prism::ParenthesesNode) && expression.body&.body&.size == 1

      case expression
      when Prism::ConstantWriteNode
        # Accept `class << (NameErrorCheckers = Object.new)` as a module which is not actually a module
        mod = @scanner.container.add_module(RDoc::NormalModule, expression.name.to_s)
      when Prism::ConstantPathNode, Prism::ConstantReadNode
        expression_name = constant_path_string(expression)
        # If a constant_path does not exist, RDoc creates a module
        mod = @scanner.find_or_create_module_path(expression_name, :module) if expression_name
      when Prism::SelfNode
        mod = @scanner.container if @scanner.container != @top_level
      end
      expression.accept(self)
      if mod
        @scanner.with_container(mod, singleton: true) do
          node.body&.accept(self)
          @scanner.process_comments_until(node.location.end_line)
        end
      else
        @scanner.skip_comments_until(node.location.end_line)
      end
    end

    def visit_def_node(node)
      start_line = node.location.start_line
      args_end_line = node.parameters&.location&.end_line || start_line
      end_line = node.location.end_line
      @scanner.process_comments_until(start_line - 1)

      case node.receiver
      when Prism::NilNode, Prism::TrueNode, Prism::FalseNode
        visibility = :public
        singleton = false
        receiver_name =
          case node.receiver
          when Prism::NilNode
            'NilClass'
          when Prism::TrueNode
            'TrueClass'
          when Prism::FalseNode
            'FalseClass'
          end
        receiver_fallback_type = :class
      when Prism::SelfNode
        # singleton method of a singleton class is not documentable
        return if @scanner.singleton
        visibility = :public
        singleton = true
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        visibility = :public
        singleton = true
        receiver_name = constant_path_string(node.receiver)
        receiver_fallback_type = :module
        return unless receiver_name
      when nil
        visibility = @scanner.visibility
        singleton = @scanner.singleton
      else
        # `def (unknown expression).method_name` is not documentable
        return
      end
      name = node.name.to_s
      params, block_params, calls_super = MethodSignatureVisitor.scan_signature(node)
      tokens = @scanner.visible_tokens_from_location(node.location)

      @scanner.add_method(
        name,
        receiver_name: receiver_name,
        receiver_fallback_type: receiver_fallback_type,
        visibility: visibility,
        singleton: singleton,
        params: params,
        block_params: block_params,
        calls_super: calls_super,
        tokens: tokens,
        start_line: start_line,
        args_end_line: args_end_line,
        end_line: end_line
      )
    ensure
      @scanner.skip_comments_until(end_line)
    end

    def visit_constant_path_write_node(node)
      @scanner.process_comments_until(node.location.start_line - 1)
      path = constant_path_string(node.target)
      return unless path

      @scanner.add_constant(
        path,
        constant_path_string(node.value) || node.value.slice,
        node.location.start_line,
        node.location.end_line
      )
      @scanner.skip_comments_until(node.location.end_line)
      # Do not traverse rhs not to document `A::B = Struct.new{def undocumentable_method; end}`
    end

    def visit_constant_write_node(node)
      @scanner.process_comments_until(node.location.start_line - 1)
      @scanner.add_constant(
        node.name.to_s,
        constant_path_string(node.value) || node.value.slice,
        node.location.start_line,
        node.location.end_line
      )
      @scanner.skip_comments_until(node.location.end_line)
      # Do not traverse rhs not to document `A = Struct.new{def undocumentable_method; end}`
    end

    private

    def constant_arguments_names(call_node)
      return unless call_node.arguments
      names = call_node.arguments.arguments.map { |arg| constant_path_string(arg) }
      names.all? ? names : nil
    end

    def symbol_arguments(call_node)
      arguments_node = call_node.arguments
      return unless arguments_node && arguments_node.arguments.all? { |arg| arg.is_a?(Prism::SymbolNode)}
      arguments_node.arguments.map { |arg| arg.value.to_sym }
    end

    def visibility_method_arguments(call_node, singleton:)
      arguments_node = call_node.arguments
      return unless arguments_node
      symbols = symbol_arguments(call_node)
      if symbols
        # module_function :foo, :bar
        return symbols.map(&:to_s)
      else
        return unless arguments_node.arguments.size == 1
        arg = arguments_node.arguments.first
        return unless arg.is_a?(Prism::DefNode)

        if singleton
          # `private_class_method def foo; end` `private_class_method def not_self.foo; end` should be ignored
          return unless arg.receiver.is_a?(Prism::SelfNode)
        else
          # `module_function def something.foo` should be ignored
          return if arg.receiver
        end
        # `module_function def foo; end` or `private_class_method def self.foo; end`
        [arg.name.to_s]
      end
    end

    def constant_path_string(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        parent_name = node.parent ? constant_path_string(node.parent) : ''
        "#{parent_name}::#{node.name}" if parent_name
      end
    end

    def _visit_call_require(call_node)
      return unless call_node.arguments&.arguments&.size == 1
      arg = call_node.arguments.arguments.first
      return unless arg.is_a?(Prism::StringNode)
      @scanner.container.add_require(RDoc::Require.new(arg.unescaped, nil))
    end

    def _visit_call_module_function(call_node)
      yield
      return if @scanner.singleton
      names = visibility_method_arguments(call_node, singleton: false)&.map(&:to_s)
      @scanner.change_method_to_module_function(names) if names
    end

    def _visit_call_public_private_class_method(call_node, visibility)
      yield
      return if @scanner.singleton
      names = visibility_method_arguments(call_node, singleton: true)
      @scanner.change_method_visibility(names, visibility, singleton: true) if names
    end

    def _visit_call_public_private_protected(call_node, visibility)
      arguments_node = call_node.arguments
      if arguments_node.nil? # `public` `private`
        @scanner.visibility = visibility
      else # `public :foo, :bar`, `private def foo; end`
        yield
        names = visibility_method_arguments(call_node, singleton: false)
        @scanner.change_method_visibility(names, visibility) if names
      end
    end

    def _visit_call_alias_method(call_node)
      new_name, old_name, *rest = symbol_arguments(call_node)
      return unless old_name && new_name && rest.empty?
      @scanner.add_alias_method(old_name.to_s, new_name.to_s, call_node.location.start_line)
    end

    def _visit_call_include(call_node)
      names = constant_arguments_names(call_node)
      line_no = call_node.location.start_line
      return unless names

      if @scanner.singleton
        @scanner.add_extends(names, line_no)
      else
        @scanner.add_includes(names, line_no)
      end
    end

    def _visit_call_extend(call_node)
      names = constant_arguments_names(call_node)
      @scanner.add_extends(names, call_node.location.start_line) if names && !@scanner.singleton
    end

    def _visit_call_public_constant(call_node)
      return if @scanner.singleton
      names = symbol_arguments(call_node)
      @scanner.container.set_constant_visibility_for(names.map(&:to_s), :public) if names
    end

    def _visit_call_private_constant(call_node)
      return if @scanner.singleton
      names = symbol_arguments(call_node)
      @scanner.container.set_constant_visibility_for(names.map(&:to_s), :private) if names
    end

    def _visit_call_attr_reader_writer_accessor(call_node, rw)
      names = symbol_arguments(call_node)
      @scanner.add_attributes(names.map(&:to_s), rw, call_node.location.start_line) if names
    end
    class MethodSignatureVisitor < Prism::Visitor # :nodoc:
      class << self
        def scan_signature(def_node)
          visitor = new
          def_node.body&.accept(visitor)
          params = "(#{def_node.parameters&.slice})"
          block_params = visitor.yields.first
          [params, block_params, visitor.calls_super]
        end
      end

      attr_reader :params, :yields, :calls_super

      def initialize
        @params = nil
        @calls_super = false
        @yields = []
      end

      def visit_def_node(node)
        # stop traverse inside nested def
      end

      def visit_yield_node(node)
        @yields << (node.arguments&.slice || '')
      end

      def visit_super_node(node)
        @calls_super = true
        super
      end

      def visit_forwarding_super_node(node)
        @calls_super = true
      end
    end
  end
end
