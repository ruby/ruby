##
# This file contains stuff stolen outright from:
#
#   rtags.rb -
#   ruby-lex.rb - ruby lexcal analyzer
#   ruby-token.rb - ruby tokens
#       by Keiju ISHITSUKA (Nippon Rational Inc.)
#

$TOKEN_DEBUG ||= nil

##
# Extracts code elements from a source file returning a TopLevel object
# containing the constituent file elements.
#
# This file is based on rtags
#
# RubyParser understands how to document:
# * classes
# * modules
# * methods
# * constants
# * aliases
# * private, public, protected
# * private_class_function, public_class_function
# * module_function
# * attr, attr_reader, attr_writer, attr_accessor
# * extra accessors given on the command line
# * metaprogrammed methods
# * require
# * include
#
# == Method Arguments
#
#--
# NOTE: I don't think this works, needs tests, remove the paragraph following
# this block when known to work
#
# The parser extracts the arguments from the method definition.  You can
# override this with a custom argument definition using the :args: directive:
#
#   ##
#   # This method tries over and over until it is tired
#
#   def go_go_go(thing_to_try, tries = 10) # :args: thing_to_try
#     puts thing_to_try
#     go_go_go thing_to_try, tries - 1
#   end
#
# If you have a more-complex set of overrides you can use the :call-seq:
# directive:
#++
#
# The parser extracts the arguments from the method definition.  You can
# override this with a custom argument definition using the :call-seq:
# directive:
#
#   ##
#   # This method can be called with a range or an offset and length
#   #
#   # :call-seq:
#   #   my_method(Range)
#   #   my_method(offset, length)
#
#   def my_method(*args)
#   end
#
# The parser extracts +yield+ expressions from method bodies to gather the
# yielded argument names.  If your method manually calls a block instead of
# yielding or you want to override the discovered argument names use
# the :yields: directive:
#
#   ##
#   # My method is awesome
#
#   def my_method(&block) # :yields: happy, times
#     block.call 1, 2
#   end
#
# == Metaprogrammed Methods
#
# To pick up a metaprogrammed method, the parser looks for a comment starting
# with '##' before an identifier:
#
#   ##
#   # This is a meta-programmed method!
#
#   add_my_method :meta_method, :arg1, :arg2
#
# The parser looks at the token after the identifier to determine the name, in
# this example, :meta_method.  If a name cannot be found, a warning is printed
# and 'unknown is used.
#
# You can force the name of a method using the :method: directive:
#
#   ##
#   # :method: some_method!
#
# By default, meta-methods are instance methods.  To indicate that a method is
# a singleton method instead use the :singleton-method: directive:
#
#   ##
#   # :singleton-method:
#
# You can also use the :singleton-method: directive with a name:
#
#   ##
#   # :singleton-method: some_method!
#
# You can define arguments for metaprogrammed methods via either the
# :call-seq:, :arg: or :args: directives.
#
# Additionally you can mark a method as an attribute by
# using :attr:, :attr_reader:, :attr_writer: or :attr_accessor:.  Just like
# for :method:, the name is optional.
#
#   ##
#   # :attr_reader: my_attr_name
#
# == Hidden methods and attributes
#
# You can provide documentation for methods that don't appear using
# the :method:, :singleton-method: and :attr: directives:
#
#   ##
#   # :attr_writer: ghost_writer
#   # There is an attribute here, but you can't see it!
#
#   ##
#   # :method: ghost_method
#   # There is a method here, but you can't see it!
#
#   ##
#   # this is a comment for a regular method
#
#   def regular_method() end
#
# Note that by default, the :method: directive will be ignored if there is a
# standard rdocable item following it.

class RDoc::Parser::Ruby < RDoc::Parser

  parse_files_matching(/\.rbw?$/)

  include RDoc::RubyToken
  include RDoc::TokenStream
  include RDoc::Parser::RubyTools

  ##
  # RDoc::NormalClass type

  NORMAL = "::"

  ##
  # RDoc::SingleClass type

  SINGLE = "<<"

  ##
  # Creates a new Ruby parser.

  def initialize(top_level, file_name, content, options, stats)
    super

    @size = 0
    @token_listeners = nil
    @scanner = RDoc::RubyLex.new content, @options
    @scanner.exception_on_syntax_error = false
    @prev_seek = nil
    @markup = @options.markup
    @track_visibility = :nodoc != @options.visibility

    @encoding = nil
    @encoding = @options.encoding if Object.const_defined? :Encoding

    reset
  end

  ##
  # Retrieves the read token stream and replaces +pattern+ with +replacement+
  # using gsub.  If the result is only a ";" returns an empty string.

  def get_tkread_clean pattern, replacement # :nodoc:
    read = get_tkread.gsub(pattern, replacement).strip
    return '' if read == ';'
    read
  end

  ##
  # Extracts the visibility information for the visibility token +tk+.
  #
  # Returns the visibility type (a string), the visibility (a symbol) and
  # +singleton+ if the methods following should be converted to singleton
  # methods.

  def get_visibility_information tk # :nodoc:
    vis_type  = tk.name
    singleton = false

    vis =
      case vis_type
      when 'private'   then :private
      when 'protected' then :protected
      when 'public'    then :public
      when 'private_class_method' then
        singleton = true
        :private
      when 'public_class_method' then
        singleton = true
        :public
      when 'module_function' then
        singleton = true
        :public
      else
        raise RDoc::Error, "Invalid visibility: #{tk.name}"
      end

    return vis_type, vis, singleton
  end

  ##
  # Look for the first comment in a file that isn't a shebang line.

  def collect_first_comment
    skip_tkspace
    comment = ''
    comment.force_encoding @encoding if @encoding
    first_line = true

    tk = get_tk

    while TkCOMMENT === tk
      if first_line and tk.text =~ /\A#!/ then
        skip_tkspace
        tk = get_tk
      elsif first_line and tk.text =~ /\A#\s*-\*-/ then
        first_line = false
        skip_tkspace
        tk = get_tk
      else
        first_line = false
        comment << tk.text << "\n"
        tk = get_tk

        if TkNL === tk then
          skip_tkspace false
          tk = get_tk
        end
      end
    end

    unget_tk tk

    new_comment comment
  end

  ##
  # Consumes trailing whitespace from the token stream

  def consume_trailing_spaces # :nodoc:
    get_tkread
    skip_tkspace false
  end

  ##
  # Creates a new attribute in +container+ with +name+.

  def create_attr container, single, name, rw, comment # :nodoc:
    att = RDoc::Attr.new get_tkread, name, rw, comment, single == SINGLE
    record_location att

    container.add_attribute att
    @stats.add_attribute att

    att
  end

  ##
  # Creates a module alias in +container+ at +rhs_name+ (or at the top-level
  # for "::") with the name from +constant+.

  def create_module_alias container, constant, rhs_name # :nodoc:
    mod = if rhs_name =~ /^::/ then
            @store.find_class_or_module rhs_name
          else
            container.find_module_named rhs_name
          end

    container.add_module_alias mod, constant.name, @top_level if mod
  end

  ##
  # Aborts with +msg+

  def error(msg)
    msg = make_message msg

    abort msg
  end

  ##
  # Looks for a true or false token.  Returns false if TkFALSE or TkNIL are
  # found.

  def get_bool
    skip_tkspace
    tk = get_tk
    case tk
    when TkTRUE
      true
    when TkFALSE, TkNIL
      false
    else
      unget_tk tk
      true
    end
  end

  ##
  # Look for the name of a class of module (optionally with a leading :: or
  # with :: separated named) and return the ultimate name, the associated
  # container, and the given name (with the ::).

  def get_class_or_module container, ignore_constants = false
    skip_tkspace
    name_t = get_tk
    given_name = ''

    # class ::A -> A is in the top level
    case name_t
    when TkCOLON2, TkCOLON3 then # bug
      name_t = get_tk
      container = @top_level
      given_name << '::'
    end

    skip_tkspace false
    given_name << name_t.name

    while TkCOLON2 === peek_tk do
      prev_container = container
      container = container.find_module_named name_t.name
      container ||=
        if ignore_constants then
          RDoc::Context.new
        else
          c = prev_container.add_module RDoc::NormalModule, name_t.name
          c.ignore unless prev_container.document_children
          @top_level.add_to_classes_or_modules c
          c
        end

      record_location container

      get_tk
      skip_tkspace false
      name_t = get_tk
      given_name << '::' << name_t.name
    end

    skip_tkspace false

    return [container, name_t, given_name]
  end

  ##
  # Return a superclass, which can be either a constant of an expression

  def get_class_specification
    case peek_tk
    when TkSELF then return 'self'
    when TkGVAR then return ''
    end

    res = get_constant

    skip_tkspace false

    get_tkread # empty out read buffer

    tk = get_tk

    case tk
    when TkNL, TkCOMMENT, TkSEMICOLON then
      unget_tk(tk)
      return res
    end

    res += parse_call_parameters(tk)
    res
  end

  ##
  # Parse a constant, which might be qualified by one or more class or module
  # names

  def get_constant
    res = ""
    skip_tkspace false
    tk = get_tk

    while TkCOLON2 === tk or TkCOLON3 === tk or TkCONSTANT === tk do
      res += tk.name
      tk = get_tk
    end

    unget_tk(tk)
    res
  end

  ##
  # Get a constant that may be surrounded by parens

  def get_constant_with_optional_parens
    skip_tkspace false

    nest = 0

    while TkLPAREN === (tk = peek_tk) or TkfLPAREN === tk do
      get_tk
      skip_tkspace
      nest += 1
    end

    name = get_constant

    while nest > 0
      skip_tkspace
      tk = get_tk
      nest -= 1 if TkRPAREN === tk
    end

    name
  end

  ##
  # Little hack going on here. In the statement:
  #
  #   f = 2*(1+yield)
  #
  # We see the RPAREN as the next token, so we need to exit early.  This still
  # won't catch all cases (such as "a = yield + 1"

  def get_end_token tk # :nodoc:
    case tk
    when TkLPAREN, TkfLPAREN
      TkRPAREN
    when TkRPAREN
      nil
    else
      TkNL
    end
  end

  ##
  # Retrieves the method container for a singleton method.

  def get_method_container container, name_t # :nodoc:
    prev_container = container
    container = container.find_module_named(name_t.name)

    unless container then
      constant = prev_container.constants.find do |const|
        const.name == name_t.name
      end

      if constant then
        parse_method_dummy prev_container
        return
      end
    end

    unless container then
      # TODO seems broken, should starting at Object in @store
      obj = name_t.name.split("::").inject(Object) do |state, item|
        state.const_get(item)
      end rescue nil

      type = obj.class == Class ? RDoc::NormalClass : RDoc::NormalModule

      unless [Class, Module].include?(obj.class) then
        warn("Couldn't find #{name_t.name}. Assuming it's a module")
      end

      if type == RDoc::NormalClass then
        sclass = obj.superclass ? obj.superclass.name : nil
        container = prev_container.add_class type, name_t.name, sclass
      else
        container = prev_container.add_module type, name_t.name
      end

      record_location container
    end

    container
  end

  ##
  # Extracts a name or symbol from the token stream.

  def get_symbol_or_name
    tk = get_tk
    case tk
    when TkSYMBOL then
      text = tk.text.sub(/^:/, '')

      if TkASSIGN === peek_tk then
        get_tk
        text << '='
      end

      text
    when TkId, TkOp then
      tk.name
    when TkAMPER,
         TkDSTRING,
         TkSTAR,
         TkSTRING then
      tk.text
    else
      raise RDoc::Error, "Name or symbol expected (got #{tk})"
    end
  end

  def stop_at_EXPR_END # :nodoc:
    @scanner.lex_state == :EXPR_END || !@scanner.continue
  end

  ##
  # Marks containers between +container+ and +ancestor+ as ignored

  def suppress_parents container, ancestor # :nodoc:
    while container and container != ancestor do
      container.suppress unless container.documented?
      container = container.parent
    end
  end

  ##
  # Look for directives in a normal comment block:
  #
  #   # :stopdoc:
  #   # Don't display comment from this point forward
  #
  # This routine modifies its +comment+ parameter.

  def look_for_directives_in context, comment
    @preprocess.handle comment, context do |directive, param|
      case directive
      when 'method', 'singleton-method',
           'attr', 'attr_accessor', 'attr_reader', 'attr_writer' then
        false # handled elsewhere
      when 'section' then
        context.set_current_section param, comment.dup
        comment.text = ''
        break
      end
    end

    remove_private_comments comment
  end

  ##
  # Adds useful info about the parser to +message+

  def make_message message
    prefix = "#{@file_name}:"

    prefix << "#{@scanner.line_no}:#{@scanner.char_no}:" if @scanner

    "#{prefix} #{message}"
  end

  ##
  # Creates a comment with the correct format

  def new_comment comment
    c = RDoc::Comment.new comment, @top_level
    c.format = @markup
    c
  end

  ##
  # Creates an RDoc::Attr for the name following +tk+, setting the comment to
  # +comment+.

  def parse_attr(context, single, tk, comment)
    offset  = tk.seek
    line_no = tk.line_no

    args = parse_symbol_arg 1
    if args.size > 0 then
      name = args[0]
      rw = "R"
      skip_tkspace false
      tk = get_tk

      if TkCOMMA === tk then
        rw = "RW" if get_bool
      else
        unget_tk tk
      end

      att = create_attr context, single, name, rw, comment
      att.offset = offset
      att.line   = line_no

      read_documentation_modifiers att, RDoc::ATTR_MODIFIERS
    else
      warn "'attr' ignored - looks like a variable"
    end
  end

  ##
  # Creates an RDoc::Attr for each attribute listed after +tk+, setting the
  # comment for each to +comment+.

  def parse_attr_accessor(context, single, tk, comment)
    offset  = tk.seek
    line_no = tk.line_no

    args = parse_symbol_arg
    rw = "?"

    tmp = RDoc::CodeObject.new
    read_documentation_modifiers tmp, RDoc::ATTR_MODIFIERS
    # TODO In most other places we let the context keep track of document_self
    # and add found items appropriately but here we do not.  I'm not sure why.
    return if @track_visibility and not tmp.document_self

    case tk.name
    when "attr_reader"   then rw = "R"
    when "attr_writer"   then rw = "W"
    when "attr_accessor" then rw = "RW"
    else
      rw = '?'
    end

    for name in args
      att = create_attr context, single, name, rw, comment
      att.offset = offset
      att.line   = line_no
    end
  end

  ##
  # Parses an +alias+ in +context+ with +comment+

  def parse_alias(context, single, tk, comment)
    offset  = tk.seek
    line_no = tk.line_no

    skip_tkspace

    if TkLPAREN === peek_tk then
      get_tk
      skip_tkspace
    end

    new_name = get_symbol_or_name

    @scanner.lex_state = :EXPR_FNAME

    skip_tkspace
    if TkCOMMA === peek_tk then
      get_tk
      skip_tkspace
    end

    begin
      old_name = get_symbol_or_name
    rescue RDoc::Error
      return
    end

    al = RDoc::Alias.new(get_tkread, old_name, new_name, comment,
                         single == SINGLE)
    record_location al
    al.offset = offset
    al.line   = line_no

    read_documentation_modifiers al, RDoc::ATTR_MODIFIERS
    context.add_alias al
    @stats.add_alias al

    al
  end

  ##
  # Extracts call parameters from the token stream.

  def parse_call_parameters(tk)
    end_token = case tk
                when TkLPAREN, TkfLPAREN
                  TkRPAREN
                when TkRPAREN
                  return ""
                else
                  TkNL
                end
    nest = 0

    loop do
      case tk
      when TkSEMICOLON
        break
      when TkLPAREN, TkfLPAREN
        nest += 1
      when end_token
        if end_token == TkRPAREN
          nest -= 1
          break if @scanner.lex_state == :EXPR_END and nest <= 0
        else
          break unless @scanner.continue
        end
      when TkCOMMENT, TkASSIGN, TkOPASGN
        unget_tk(tk)
        break
      when nil then
        break
      end
      tk = get_tk
    end

    get_tkread_clean "\n", " "
  end

  ##
  # Parses a class in +context+ with +comment+

  def parse_class container, single, tk, comment
    offset  = tk.seek
    line_no = tk.line_no

    declaration_context = container
    container, name_t, given_name = get_class_or_module container

    cls =
      case name_t
      when TkCONSTANT
        parse_class_regular container, declaration_context, single,
          name_t, given_name, comment
      when TkLSHFT
        case name = get_class_specification
        when 'self', container.name
          parse_statements container, SINGLE
          return # don't update offset or line
        else
          parse_class_singleton container, name, comment
        end
      else
        warn "Expected class name or '<<'. Got #{name_t.class}: #{name_t.text.inspect}"
        return
      end

    cls.offset = offset
    cls.line   = line_no

    cls
  end

  ##
  # Parses and creates a regular class

  def parse_class_regular container, declaration_context, single, # :nodoc:
                          name_t, given_name, comment
    superclass = '::Object'

    if given_name =~ /^::/ then
      declaration_context = @top_level
      given_name = $'
    end

    if TkLT === peek_tk then
      get_tk
      skip_tkspace
      superclass = get_class_specification
      superclass = '(unknown)' if superclass.empty?
    end

    cls_type = single == SINGLE ? RDoc::SingleClass : RDoc::NormalClass
    cls = declaration_context.add_class cls_type, given_name, superclass
    cls.ignore unless container.document_children

    read_documentation_modifiers cls, RDoc::CLASS_MODIFIERS
    record_location cls

    cls.add_comment comment, @top_level

    @top_level.add_to_classes_or_modules cls
    @stats.add_class cls

    suppress_parents container, declaration_context unless cls.document_self

    parse_statements cls

    cls
  end

  ##
  # Parses a singleton class in +container+ with the given +name+ and
  # +comment+.

  def parse_class_singleton container, name, comment # :nodoc:
    other = @store.find_class_named name

    unless other then
      if name =~ /^::/ then
        name = $'
        container = @top_level
      end

      other = container.add_module RDoc::NormalModule, name
      record_location other

      # class << $gvar
      other.ignore if name.empty?

      other.add_comment comment, @top_level
    end

    # notify :nodoc: all if not a constant-named class/module
    # (and remove any comment)
    unless name =~ /\A(::)?[A-Z]/ then
      other.document_self = nil
      other.document_children = false
      other.clear_comment
    end

    @top_level.add_to_classes_or_modules other
    @stats.add_class other

    read_documentation_modifiers other, RDoc::CLASS_MODIFIERS
    parse_statements(other, SINGLE)

    other
  end

  ##
  # Parses a constant in +context+ with +comment+.  If +ignore_constants+ is
  # true, no found constants will be added to RDoc.

  def parse_constant container, tk, comment, ignore_constants = false
    prev_container = container
    offset  = tk.seek
    line_no = tk.line_no

    name = tk.name
    skip_tkspace false

    return unless name =~ /^\w+$/

    eq_tk = get_tk

    if TkCOLON2 === eq_tk then
      unget_tk eq_tk
      unget_tk tk

      container, name_t, = get_class_or_module container, ignore_constants

      name = name_t.name

      eq_tk = get_tk
    end

    unless TkASSIGN === eq_tk then
      suppress_parents container, prev_container

      unget_tk eq_tk
      return false
    end

    if TkGT === peek_tk then
      unget_tk eq_tk
      return
    end

    value = ''
    con = RDoc::Constant.new name, value, comment

    body = parse_constant_body container, con

    return unless body

    value.replace body
    record_location con
    con.offset = offset
    con.line   = line_no
    read_documentation_modifiers con, RDoc::CONSTANT_MODIFIERS

    @stats.add_constant con
    con = container.add_constant con

    true
  end

  def parse_constant_body container, constant # :nodoc:
    nest     = 0
    rhs_name = ''

    get_tkread

    tk = get_tk

    loop do
      case tk
      when TkSEMICOLON then
        break if nest <= 0
      when TkLPAREN, TkfLPAREN, TkLBRACE, TkfLBRACE, TkLBRACK, TkfLBRACK,
           TkDO, TkIF, TkUNLESS, TkCASE, TkDEF, TkBEGIN then
        nest += 1
      when TkRPAREN, TkRBRACE, TkRBRACK, TkEND then
        nest -= 1
      when TkCOMMENT then
        if nest <= 0 and stop_at_EXPR_END then
          unget_tk tk
          break
        else
          unget_tk tk
          read_documentation_modifiers constant, RDoc::CONSTANT_MODIFIERS
        end
      when TkCONSTANT then
        rhs_name << tk.name

        if nest <= 0 and TkNL === peek_tk then
          create_module_alias container, constant, rhs_name
          break
        end
      when TkNL then
        if nest <= 0 and stop_at_EXPR_END then
          unget_tk tk
          break
        end
      when TkCOLON2, TkCOLON3 then
        rhs_name << '::'
      when nil then
        break
      end
      tk = get_tk
    end

    get_tkread_clean(/^[ \t]+/, '')
  end

  ##
  # Generates an RDoc::Method or RDoc::Attr from +comment+ by looking for
  # :method: or :attr: directives in +comment+.

  def parse_comment container, tk, comment
    return parse_comment_tomdoc container, tk, comment if @markup == 'tomdoc'
    column  = tk.char_no
    offset  = tk.seek
    line_no = tk.line_no

    text = comment.text

    singleton = !!text.sub!(/(^# +:?)(singleton-)(method:)/, '\1\3')

    co =
      if text.sub!(/^# +:?method: *(\S*).*?\n/i, '') then
        parse_comment_ghost container, text, $1, column, line_no, comment
      elsif text.sub!(/# +:?(attr(_reader|_writer|_accessor)?): *(\S*).*?\n/i, '') then
        parse_comment_attr container, $1, $3, comment
      end

    if co then
      co.singleton = singleton
      co.offset    = offset
      co.line      = line_no
    end

    true
  end

  ##
  # Parse a comment that is describing an attribute in +container+ with the
  # given +name+ and +comment+.

  def parse_comment_attr container, type, name, comment # :nodoc:
    return if name.empty?

    rw = case type
         when 'attr_reader' then 'R'
         when 'attr_writer' then 'W'
         else 'RW'
         end

    create_attr container, NORMAL, name, rw, comment
  end

  def parse_comment_ghost container, text, name, column, line_no, # :nodoc:
                          comment
    name = nil if name.empty?

    meth = RDoc::GhostMethod.new get_tkread, name
    record_location meth

    meth.start_collecting_tokens
    indent = TkSPACE.new 0, 1, 1
    indent.set_text " " * column

    position_comment = TkCOMMENT.new 0, line_no, 1
    position_comment.set_text "# File #{@top_level.relative_name}, line #{line_no}"
    meth.add_tokens [position_comment, NEWLINE_TOKEN, indent]

    meth.params =
      if text.sub!(/^#\s+:?args?:\s*(.*?)\s*$/i, '') then
        $1
      else
        ''
      end

    comment.normalize
    comment.extract_call_seq meth

    return unless meth.name

    container.add_method meth

    meth.comment = comment

    @stats.add_method meth

    meth
  end

  ##
  # Creates an RDoc::Method on +container+ from +comment+ if there is a
  # Signature section in the comment

  def parse_comment_tomdoc container, tk, comment
    return unless signature = RDoc::TomDoc.signature(comment)
    offset  = tk.seek
    line_no = tk.line_no

    name, = signature.split %r%[ \(]%, 2

    meth = RDoc::GhostMethod.new get_tkread, name
    record_location meth
    meth.offset    = offset
    meth.line      = line_no

    meth.start_collecting_tokens
    indent = TkSPACE.new 0, 1, 1
    indent.set_text " " * offset

    position_comment = TkCOMMENT.new 0, line_no, 1
    position_comment.set_text "# File #{@top_level.relative_name}, line #{line_no}"
    meth.add_tokens [position_comment, NEWLINE_TOKEN, indent]

    meth.call_seq = signature

    comment.normalize

    return unless meth.name

    container.add_method meth

    meth.comment = comment

    @stats.add_method meth
  end

  ##
  # Parses an +include+ or +extend+, indicated by the +klass+ and adds it to
  # +container+ # with +comment+

  def parse_extend_or_include klass, container, comment # :nodoc:
    loop do
      skip_tkspace_comment

      name = get_constant_with_optional_parens

      unless name.empty? then
        obj = container.add klass, name, comment
        record_location obj
      end

      return unless TkCOMMA === peek_tk

      get_tk
    end
  end

  ##
  # Parses identifiers that can create new methods or change visibility.
  #
  # Returns true if the comment was not consumed.

  def parse_identifier container, single, tk, comment # :nodoc:
    case tk.name
    when 'private', 'protected', 'public', 'private_class_method',
         'public_class_method', 'module_function' then
      parse_visibility container, single, tk
      return true
    when 'attr' then
      parse_attr container, single, tk, comment
    when /^attr_(reader|writer|accessor)$/ then
      parse_attr_accessor container, single, tk, comment
    when 'alias_method' then
      parse_alias container, single, tk, comment
    when 'require', 'include' then
      # ignore
    else
      if comment.text =~ /\A#\#$/ then
        case comment.text
        when /^# +:?attr(_reader|_writer|_accessor)?:/ then
          parse_meta_attr container, single, tk, comment
        else
          method = parse_meta_method container, single, tk, comment
          method.params = container.params if
            container.params
          method.block_params = container.block_params if
            container.block_params
        end
      end
    end

    false
  end

  ##
  # Parses a meta-programmed attribute and creates an RDoc::Attr.
  #
  # To create foo and bar attributes on class C with comment "My attributes":
  #
  #   class C
  #
  #     ##
  #     # :attr:
  #     #
  #     # My attributes
  #
  #     my_attr :foo, :bar
  #
  #   end
  #
  # To create a foo attribute on class C with comment "My attribute":
  #
  #   class C
  #
  #     ##
  #     # :attr: foo
  #     #
  #     # My attribute
  #
  #     my_attr :foo, :bar
  #
  #   end

  def parse_meta_attr(context, single, tk, comment)
    args = parse_symbol_arg
    rw = "?"

    # If nodoc is given, don't document any of them

    tmp = RDoc::CodeObject.new
    read_documentation_modifiers tmp, RDoc::ATTR_MODIFIERS

    if comment.text.sub!(/^# +:?(attr(_reader|_writer|_accessor)?): *(\S*).*?\n/i, '') then
      rw = case $1
           when 'attr_reader' then 'R'
           when 'attr_writer' then 'W'
           else 'RW'
           end
      name = $3 unless $3.empty?
    end

    if name then
      att = create_attr context, single, name, rw, comment
    else
      args.each do |attr_name|
        att = create_attr context, single, attr_name, rw, comment
      end
    end

    att
  end

  ##
  # Parses a meta-programmed method

  def parse_meta_method(container, single, tk, comment)
    column  = tk.char_no
    offset  = tk.seek
    line_no = tk.line_no

    start_collecting_tokens
    add_token tk
    add_token_listener self

    skip_tkspace false

    singleton = !!comment.text.sub!(/(^# +:?)(singleton-)(method:)/, '\1\3')

    name = parse_meta_method_name comment, tk

    return unless name

    meth = RDoc::MetaMethod.new get_tkread, name
    record_location meth
    meth.offset = offset
    meth.line   = line_no
    meth.singleton = singleton

    remove_token_listener self

    meth.start_collecting_tokens
    indent = TkSPACE.new 0, 1, 1
    indent.set_text " " * column

    position_comment = TkCOMMENT.new 0, line_no, 1
    position_comment.value = "# File #{@top_level.relative_name}, line #{line_no}"
    meth.add_tokens [position_comment, NEWLINE_TOKEN, indent]
    meth.add_tokens @token_stream

    parse_meta_method_params container, single, meth, tk, comment

    meth.comment = comment

    @stats.add_method meth

    meth
  end

  ##
  # Parses the name of a metaprogrammed method.  +comment+ is used to
  # determine the name while +tk+ is used in an error message if the name
  # cannot be determined.

  def parse_meta_method_name comment, tk # :nodoc:
    if comment.text.sub!(/^# +:?method: *(\S*).*?\n/i, '') then
      return $1 unless $1.empty?
    end

    name_t = get_tk

    case name_t
    when TkSYMBOL then
      name_t.text[1..-1]
    when TkSTRING then
      name_t.value[1..-2]
    when TkASSIGN then # ignore
      remove_token_listener self

      nil
    else
      warn "unknown name token #{name_t.inspect} for meta-method '#{tk.name}'"
      'unknown'
    end
  end

  ##
  # Parses the parameters and block for a meta-programmed method.

  def parse_meta_method_params container, single, meth, tk, comment # :nodoc:
    token_listener meth do
      meth.params = ''

      comment.normalize
      comment.extract_call_seq meth

      container.add_method meth

      last_tk = tk

      while tk = get_tk do
        case tk
        when TkSEMICOLON then
          break
        when TkNL then
          break unless last_tk and TkCOMMA === last_tk
        when TkSPACE then
          # expression continues
        when TkDO then
          parse_statements container, single, meth
          break
        else
          last_tk = tk
        end
      end
    end
  end

  ##
  # Parses a normal method defined by +def+

  def parse_method(container, single, tk, comment)
    singleton = nil
    added_container = false
    name = nil
    column  = tk.char_no
    offset  = tk.seek
    line_no = tk.line_no

    start_collecting_tokens
    add_token tk

    token_listener self do
      prev_container = container
      name, container, singleton = parse_method_name container
      added_container = container != prev_container
    end

    return unless name

    meth = RDoc::AnyMethod.new get_tkread, name
    meth.singleton = singleton

    record_location meth
    meth.offset = offset
    meth.line   = line_no

    meth.start_collecting_tokens
    indent = TkSPACE.new 0, 1, 1
    indent.set_text " " * column

    token = TkCOMMENT.new 0, line_no, 1
    token.set_text "# File #{@top_level.relative_name}, line #{line_no}"
    meth.add_tokens [token, NEWLINE_TOKEN, indent]
    meth.add_tokens @token_stream

    parse_method_params_and_body container, single, meth, added_container

    comment.normalize
    comment.extract_call_seq meth

    meth.comment = comment

    @stats.add_method meth
  end

  ##
  # Parses the parameters and body of +meth+

  def parse_method_params_and_body container, single, meth, added_container
    token_listener meth do
      @scanner.continue = false
      parse_method_parameters meth

      if meth.document_self or not @track_visibility then
        container.add_method meth
      elsif added_container then
        container.document_self = false
      end

      # Having now read the method parameters and documentation modifiers, we
      # now know whether we have to rename #initialize to ::new

      if meth.name == "initialize" && !meth.singleton then
        if meth.dont_rename_initialize then
          meth.visibility = :protected
        else
          meth.singleton = true
          meth.name = "new"
          meth.visibility = :public
        end
      end

      parse_statements container, single, meth
    end
  end

  ##
  # Parses a method that needs to be ignored.

  def parse_method_dummy container
    dummy = RDoc::Context.new
    dummy.parent = container
    dummy.store  = container.store
    skip_method dummy
  end

  ##
  # Parses the name of a method in +container+.
  #
  # Returns the method name, the container it is in (for def Foo.name) and if
  # it is a singleton or regular method.

  def parse_method_name container # :nodoc:
    @scanner.lex_state = :EXPR_FNAME

    skip_tkspace
    name_t = get_tk
    back_tk = skip_tkspace
    singleton = false

    case dot = get_tk
    when TkDOT, TkCOLON2 then
      singleton = true

      name, container = parse_method_name_singleton container, name_t
    else
      unget_tk dot
      back_tk.reverse_each do |token|
        unget_tk token
      end

      name = parse_method_name_regular container, name_t
    end

    return name, container, singleton
  end

  ##
  # For the given +container+ and initial name token +name_t+ the method name
  # is parsed from the token stream for a regular method.

  def parse_method_name_regular container, name_t # :nodoc:
    case name_t
    when TkSTAR, TkAMPER then
      name_t.text
    else
      unless name_t.respond_to? :name then
        warn "expected method name token, . or ::, got #{name_t.inspect}"
        skip_method container
        return
      end
      name_t.name
    end
  end

  ##
  # For the given +container+ and initial name token +name_t+ the method name
  # and the new +container+ (if necessary) are parsed from the token stream
  # for a singleton method.

  def parse_method_name_singleton container, name_t # :nodoc:
    @scanner.lex_state = :EXPR_FNAME
    skip_tkspace
    name_t2 = get_tk

    name =
      case name_t
      when TkSELF, TkMOD then
        case name_t2
          # NOTE: work around '[' being consumed early and not being re-tokenized
          # as a TkAREF
        when TkfLBRACK then
          get_tk
          '[]'
        else
          name_t2.name
        end
      when TkCONSTANT then
        name = name_t2.name

        container = get_method_container container, name_t

        return unless container

        name
      when TkIDENTIFIER, TkIVAR, TkGVAR then
        parse_method_dummy container

        nil
      when TkTRUE, TkFALSE, TkNIL then
        klass_name = "#{name_t.name.capitalize}Class"
        container = @store.find_class_named klass_name
        container ||= @top_level.add_class RDoc::NormalClass, klass_name

        name_t2.name
      else
        warn "unexpected method name token #{name_t.inspect}"
        # break
        skip_method container

        nil
      end

    return name, container
  end

  ##
  # Extracts +yield+ parameters from +method+

  def parse_method_or_yield_parameters(method = nil,
                                       modifiers = RDoc::METHOD_MODIFIERS)
    skip_tkspace false
    tk = get_tk
    end_token = get_end_token tk
    return '' unless end_token

    nest = 0

    loop do
      case tk
      when TkSEMICOLON then
        break if nest == 0
      when TkLBRACE, TkfLBRACE then
        nest += 1
      when TkRBRACE then
        nest -= 1
        if nest <= 0
          # we might have a.each { |i| yield i }
          unget_tk(tk) if nest < 0
          break
        end
      when TkLPAREN, TkfLPAREN then
        nest += 1
      when end_token then
        if end_token == TkRPAREN
          nest -= 1
          break if nest <= 0
        else
          break unless @scanner.continue
        end
      when TkRPAREN then
        nest -= 1
      when method && method.block_params.nil? && TkCOMMENT then
        unget_tk tk
        read_documentation_modifiers method, modifiers
        @read.pop
      when TkCOMMENT then
        @read.pop
      when nil then
        break
      end
      tk = get_tk
    end

    get_tkread_clean(/\s+/, ' ')
  end

  ##
  # Capture the method's parameters. Along the way, look for a comment
  # containing:
  #
  #    # yields: ....
  #
  # and add this as the block_params for the method

  def parse_method_parameters method
    res = parse_method_or_yield_parameters method

    res = "(#{res})" unless res =~ /\A\(/
    method.params = res unless method.params

    return if  method.block_params

    skip_tkspace false
    read_documentation_modifiers method, RDoc::METHOD_MODIFIERS
  end

  ##
  # Parses an RDoc::NormalModule in +container+ with +comment+

  def parse_module container, single, tk, comment
    container, name_t, = get_class_or_module container

    name = name_t.name

    mod = container.add_module RDoc::NormalModule, name
    mod.ignore unless container.document_children
    record_location mod

    read_documentation_modifiers mod, RDoc::CLASS_MODIFIERS
    mod.add_comment comment, @top_level
    parse_statements mod

    @stats.add_module mod
  end

  ##
  # Parses an RDoc::Require in +context+ containing +comment+

  def parse_require(context, comment)
    skip_tkspace_comment
    tk = get_tk

    if TkLPAREN === tk then
      skip_tkspace_comment
      tk = get_tk
    end

    name = tk.text if TkSTRING === tk

    if name then
      @top_level.add_require RDoc::Require.new(name, comment)
    else
      unget_tk tk
    end
  end

  ##
  # Parses a rescue

  def parse_rescue
    skip_tkspace false

    while tk = get_tk
      case tk
      when TkNL, TkSEMICOLON then
        break
      when TkCOMMA then
        skip_tkspace false

        get_tk if TkNL === peek_tk
      end

      skip_tkspace false
    end
  end

  ##
  # The core of the Ruby parser.

  def parse_statements(container, single = NORMAL, current_method = nil,
                       comment = new_comment(''))
    raise 'no' unless RDoc::Comment === comment
    comment.force_encoding @encoding if @encoding

    nest = 1
    save_visibility = container.visibility

    non_comment_seen = true

    while tk = get_tk do
      keep_comment = false
      try_parse_comment = false

      non_comment_seen = true unless TkCOMMENT === tk

      case tk
      when TkNL then
        skip_tkspace
        tk = get_tk

        if TkCOMMENT === tk then
          if non_comment_seen then
            # Look for RDoc in a comment about to be thrown away
            non_comment_seen = parse_comment container, tk, comment unless
              comment.empty?

            comment = ''
            comment.force_encoding @encoding if @encoding
          end

          while TkCOMMENT === tk do
            comment << tk.text << "\n"

            tk = get_tk

            if TkNL === tk then
              skip_tkspace false # leading spaces
              tk = get_tk
            end
          end

          comment = new_comment comment

          unless comment.empty? then
            look_for_directives_in container, comment

            if container.done_documenting then
              throw :eof if RDoc::TopLevel === container
              container.ongoing_visibility = save_visibility
            end
          end

          keep_comment = true
        else
          non_comment_seen = true
        end

        unget_tk tk
        keep_comment = true

      when TkCLASS then
        parse_class container, single, tk, comment

      when TkMODULE then
        parse_module container, single, tk, comment

      when TkDEF then
        parse_method container, single, tk, comment

      when TkCONSTANT then
        unless parse_constant container, tk, comment, current_method then
          try_parse_comment = true
        end

      when TkALIAS then
        parse_alias container, single, tk, comment unless current_method

      when TkYIELD then
        if current_method.nil? then
          warn "Warning: yield outside of method" if container.document_self
        else
          parse_yield container, single, tk, current_method
        end

      # Until and While can have a 'do', which shouldn't increase the nesting.
      # We can't solve the general case, but we can handle most occurrences by
      # ignoring a do at the end of a line.

      when TkUNTIL, TkWHILE then
        nest += 1
        skip_optional_do_after_expression

      # 'for' is trickier
      when TkFOR then
        nest += 1
        skip_for_variable
        skip_optional_do_after_expression

      when TkCASE, TkDO, TkIF, TkUNLESS, TkBEGIN then
        nest += 1

      when TkSUPER then
        current_method.calls_super = true if current_method

      when TkRESCUE then
        parse_rescue

      when TkIDENTIFIER then
        if nest == 1 and current_method.nil? then
          keep_comment = parse_identifier container, single, tk, comment
        end

        case tk.name
        when "require" then
          parse_require container, comment
        when "include" then
          parse_extend_or_include RDoc::Include, container, comment
        when "extend" then
          parse_extend_or_include RDoc::Extend, container, comment
        end

      when TkEND then
        nest -= 1
        if nest == 0 then
          read_documentation_modifiers container, RDoc::CLASS_MODIFIERS
          container.ongoing_visibility = save_visibility

          parse_comment container, tk, comment unless comment.empty?

          return
        end
      else
        try_parse_comment = nest == 1
      end

      if try_parse_comment then
        non_comment_seen = parse_comment container, tk, comment unless
          comment.empty?

        keep_comment = false
      end

      unless keep_comment then
        comment = new_comment ''
        comment.force_encoding @encoding if @encoding
        container.params = nil
        container.block_params = nil
      end

      consume_trailing_spaces
    end

    container.params = nil
    container.block_params = nil
  end

  ##
  # Parse up to +no+ symbol arguments

  def parse_symbol_arg(no = nil)
    skip_tkspace_comment

    case tk = get_tk
    when TkLPAREN
      parse_symbol_arg_paren no
    else
      parse_symbol_arg_space no, tk
    end
  end

  ##
  # Parses up to +no+ symbol arguments surrounded by () and places them in
  # +args+.

  def parse_symbol_arg_paren no # :nodoc:
    args = []

    loop do
      skip_tkspace_comment
      if tk1 = parse_symbol_in_arg
        args.push tk1
        break if no and args.size >= no
      end

      skip_tkspace_comment
      case tk2 = get_tk
      when TkRPAREN
        break
      when TkCOMMA
      else
        warn("unexpected token: '#{tk2.inspect}'") if $DEBUG_RDOC
        break
      end
    end

    args
  end

  ##
  # Parses up to +no+ symbol arguments separated by spaces and places them in
  # +args+.

  def parse_symbol_arg_space no, tk # :nodoc:
    args = []

    unget_tk tk
    if tk = parse_symbol_in_arg
      args.push tk
      return args if no and args.size >= no
    end

    loop do
      skip_tkspace false

      tk1 = get_tk
      unless TkCOMMA === tk1 then
        unget_tk tk1
        break
      end

      skip_tkspace_comment
      if tk = parse_symbol_in_arg
        args.push tk
        break if no and args.size >= no
      end
    end

    args
  end

  ##
  # Returns symbol text from the next token

  def parse_symbol_in_arg
    case tk = get_tk
    when TkSYMBOL
      tk.text.sub(/^:/, '')
    when TkSTRING
      eval @read[-1]
    when TkDSTRING, TkIDENTIFIER then
      nil # ignore
    else
      warn("Expected symbol or string, got #{tk.inspect}") if $DEBUG_RDOC
      nil
    end
  end

  ##
  # Parses statements in the top-level +container+

  def parse_top_level_statements container
    comment = collect_first_comment

    look_for_directives_in container, comment

    throw :eof if container.done_documenting

    @markup = comment.format

    # HACK move if to RDoc::Context#comment=
    container.comment = comment if container.document_self unless comment.empty?

    parse_statements container, NORMAL, nil, comment
  end

  ##
  # Determines the visibility in +container+ from +tk+

  def parse_visibility(container, single, tk)
    singleton = (single == SINGLE)

    vis_type, vis, singleton = get_visibility_information tk

    skip_tkspace_comment false

    case peek_tk
      # Ryan Davis suggested the extension to ignore modifiers, because he
      # often writes
      #
      #   protected unless $TESTING
      #
    when TkNL, TkUNLESS_MOD, TkIF_MOD, TkSEMICOLON then
      container.ongoing_visibility = vis
    else
      update_visibility container, vis_type, vis, singleton
    end
  end

  ##
  # Determines the block parameter for +context+

  def parse_yield(context, single, tk, method)
    return if method.block_params

    get_tkread
    @scanner.continue = false
    method.block_params = parse_method_or_yield_parameters
  end

  ##
  # Directives are modifier comments that can appear after class, module, or
  # method names. For example:
  #
  #   def fred # :yields: a, b
  #
  # or:
  #
  #   class MyClass # :nodoc:
  #
  # We return the directive name and any parameters as a two element array if
  # the name is in +allowed+.  A directive can be found anywhere up to the end
  # of the current line.

  def read_directive allowed
    tokens = []

    while tk = get_tk do
      tokens << tk

      case tk
      when TkNL, TkDEF then
        return
      when TkCOMMENT then
        return unless tk.text =~ /\s*:?([\w-]+):\s*(.*)/

        directive = $1.downcase

        return [directive, $2] if allowed.include? directive

        return
      end
    end
  ensure
    unless tokens.length == 1 and TkCOMMENT === tokens.first then
      tokens.reverse_each do |token|
        unget_tk token
      end
    end
  end

  ##
  # Handles directives following the definition for +context+ (any
  # RDoc::CodeObject) if the directives are +allowed+ at this point.
  #
  # See also RDoc::Markup::PreProcess#handle_directive

  def read_documentation_modifiers context, allowed
    directive, value = read_directive allowed

    return unless directive

    @preprocess.handle_directive '', directive, value, context do |dir, param|
      if %w[notnew not_new not-new].include? dir then
        context.dont_rename_initialize = true

        true
      end
    end
  end

  ##
  # Records the location of this +container+ in the file for this parser and
  # adds it to the list of classes and modules in the file.

  def record_location container # :nodoc:
    case container
    when RDoc::ClassModule then
      @top_level.add_to_classes_or_modules container
    end

    container.record_location @top_level
  end

  ##
  # Removes private comments from +comment+
  #--
  # TODO remove

  def remove_private_comments comment
    comment.remove_private
  end

  ##
  # Scans this Ruby file for Ruby constructs

  def scan
    reset

    catch :eof do
      begin
        parse_top_level_statements @top_level

      rescue StandardError => e
        bytes = ''

        20.times do @scanner.ungetc end
        count = 0
        60.times do |i|
          count = i
          byte = @scanner.getc
          break unless byte
          bytes << byte
        end
        count -= 20
        count.times do @scanner.ungetc end

        $stderr.puts <<-EOF

#{self.class} failure around line #{@scanner.line_no} of
#{@file_name}

        EOF

        unless bytes.empty? then
          $stderr.puts
          $stderr.puts bytes.inspect
        end

        raise e
      end
    end

    @top_level
  end

  ##
  # while, until, and for have an optional do

  def skip_optional_do_after_expression
    skip_tkspace false
    tk = get_tk
    end_token = get_end_token tk

    b_nest = 0
    nest = 0
    @scanner.continue = false

    loop do
      case tk
      when TkSEMICOLON then
        break if b_nest.zero?
      when TkLPAREN, TkfLPAREN then
        nest += 1
      when TkBEGIN then
        b_nest += 1
      when TkEND then
        b_nest -= 1
      when TkDO
        break if nest.zero?
      when end_token then
        if end_token == TkRPAREN
          nest -= 1
          break if @scanner.lex_state == :EXPR_END and nest.zero?
        else
          break unless @scanner.continue
        end
      when nil then
        break
      end
      tk = get_tk
    end

    skip_tkspace false

    get_tk if TkDO === peek_tk
  end

  ##
  # skip the var [in] part of a 'for' statement

  def skip_for_variable
    skip_tkspace false
    tk = get_tk
    skip_tkspace false
    tk = get_tk
    unget_tk(tk) unless TkIN === tk
  end

  ##
  # Skips the next method in +container+

  def skip_method container
    meth = RDoc::AnyMethod.new "", "anon"
    parse_method_parameters meth
    parse_statements container, false, meth
  end

  ##
  # Skip spaces until a comment is found

  def skip_tkspace_comment(skip_nl = true)
    loop do
      skip_tkspace skip_nl
      return unless TkCOMMENT === peek_tk
      get_tk
    end
  end

  ##
  # Updates visibility in +container+ from +vis_type+ and +vis+.

  def update_visibility container, vis_type, vis, singleton # :nodoc:
    new_methods = []

    case vis_type
    when 'module_function' then
      args = parse_symbol_arg
      container.set_visibility_for args, :private, false

      container.methods_matching args do |m|
        s_m = m.dup
        record_location s_m
        s_m.singleton = true
        new_methods << s_m
      end
    when 'public_class_method', 'private_class_method' then
      args = parse_symbol_arg

      container.methods_matching args, true do |m|
        if m.parent != container then
          m = m.dup
          record_location m
          new_methods << m
        end

        m.visibility = vis
      end
    else
      args = parse_symbol_arg
      container.set_visibility_for args, vis, singleton
    end

    new_methods.each do |method|
      case method
      when RDoc::AnyMethod then
        container.add_method method
      when RDoc::Attr then
        container.add_attribute method
      end
      method.visibility = vis
    end
  end

  ##
  # Prints +message+ to +$stderr+ unless we're being quiet

  def warn message
    @options.warn make_message message
  end

end

