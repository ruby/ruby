require 'rdoc/parser'
require 'rdoc/parser/ruby'
require 'rdoc/known_classes'

##
# We attempt to parse C extension files. Basically we look for
# the standard patterns that you find in extensions: <tt>rb_define_class,
# rb_define_method</tt> and so on. We also try to find the corresponding
# C source for the methods and extract comments, but if we fail
# we don't worry too much.
#
# The comments associated with a Ruby method are extracted from the C
# comment block associated with the routine that _implements_ that
# method, that is to say the method whose name is given in the
# <tt>rb_define_method</tt> call. For example, you might write:
#
#  /*
#   * Returns a new array that is a one-dimensional flattening of this
#   * array (recursively). That is, for every element that is an array,
#   * extract its elements into the new array.
#   *
#   *    s = [ 1, 2, 3 ]           #=> [1, 2, 3]
#   *    t = [ 4, 5, 6, [7, 8] ]   #=> [4, 5, 6, [7, 8]]
#   *    a = [ s, t, 9, 10 ]       #=> [[1, 2, 3], [4, 5, 6, [7, 8]], 9, 10]
#   *    a.flatten                 #=> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
#   */
#   static VALUE
#   rb_ary_flatten(ary)
#       VALUE ary;
#   {
#       ary = rb_obj_dup(ary);
#       rb_ary_flatten_bang(ary);
#       return ary;
#   }
#
#   ...
#
#   void
#   Init_Array()
#   {
#     ...
#     rb_define_method(rb_cArray, "flatten", rb_ary_flatten, 0);
#
# Here RDoc will determine from the rb_define_method line that there's a
# method called "flatten" in class Array, and will look for the implementation
# in the method rb_ary_flatten. It will then use the comment from that
# method in the HTML output. This method must be in the same source file
# as the rb_define_method.
#
# C classes can be diagrammed (see /tc/dl/ruby/ruby/error.c), and RDoc
# integrates C and Ruby source into one tree
#
# The comment blocks may include special directives:
#
# [Document-class: <i>name</i>]
#   This comment block is documentation for the given class. Use this
#   when the <tt>Init_xxx</tt> method is not named after the class.
#
# [Document-method: <i>name</i>]
#   This comment documents the named method. Use when RDoc cannot
#   automatically find the method from it's declaration
#
# [call-seq:  <i>text up to an empty line</i>]
#   Because C source doesn't give descripive names to Ruby-level parameters,
#   you need to document the calling sequence explicitly
#
# In addition, RDoc assumes by default that the C method implementing a
# Ruby function is in the same source file as the rb_define_method call.
# If this isn't the case, add the comment:
#
#    rb_define_method(....);  // in: filename
#
# As an example, we might have an extension that defines multiple classes
# in its Init_xxx method. We could document them using
#
#   /*
#    * Document-class:  MyClass
#    *
#    * Encapsulate the writing and reading of the configuration
#    * file. ...
#    */
#   
#   /*
#    * Document-method: read_value
#    *
#    * call-seq:
#    *   cfg.read_value(key)            -> value
#    *   cfg.read_value(key} { |key| }  -> value
#    *
#    * Return the value corresponding to +key+ from the configuration.
#    * In the second form, if the key isn't found, invoke the
#    * block and return its value.
#    */

class RDoc::Parser::C < RDoc::Parser

  parse_files_matching(/\.(?:([CcHh])\1?|c([+xp])\2|y)\z/)

  @@enclosure_classes = {}
  @@known_bodies = {}

  ##
  # Prepare to parse a C file

  def initialize(top_level, file_name, content, options, stats)
    super

    @known_classes = RDoc::KNOWN_CLASSES.dup
    @content = handle_tab_width handle_ifdefs_in(@content)
    @classes = Hash.new
    @file_dir = File.dirname(@file_name)
  end

  def do_aliases
    @content.scan(%r{rb_define_alias\s*\(\s*(\w+),\s*"([^"]+)",\s*"([^"]+)"\s*\)}m) do
      |var_name, new_name, old_name|
      class_name = @known_classes[var_name] || var_name
      class_obj  = find_class(var_name, class_name)

      as = class_obj.add_alias RDoc::Alias.new("", old_name, new_name, "")

      @stats.add_alias as
    end
  end

  def do_classes
    @content.scan(/(\w+)\s* = \s*rb_define_module\s*\(\s*"(\w+)"\s*\)/mx) do 
      |var_name, class_name|
      handle_class_module(var_name, "module", class_name, nil, nil)
    end

    # The '.' lets us handle SWIG-generated files
    @content.scan(/([\w\.]+)\s* = \s*rb_define_class\s*
              \(
                 \s*"(\w+)",
                 \s*(\w+)\s*
              \)/mx) do |var_name, class_name, parent|
      handle_class_module(var_name, "class", class_name, parent, nil)
    end

    @content.scan(/(\w+)\s*=\s*boot_defclass\s*\(\s*"(\w+?)",\s*(\w+?)\s*\)/) do
      |var_name, class_name, parent|
      parent = nil if parent == "0"
      handle_class_module(var_name, "class", class_name, parent, nil)
    end

    @content.scan(/(\w+)\s* = \s*rb_define_module_under\s*
              \(
                 \s*(\w+),
                 \s*"(\w+)"
              \s*\)/mx) do |var_name, in_module, class_name|
      handle_class_module(var_name, "module", class_name, nil, in_module)
    end

    @content.scan(/([\w\.]+)\s* = \s*rb_define_class_under\s*
              \(
                 \s*(\w+),
                 \s*"(\w+)",
                 \s*([\w\*\s\(\)\.\->]+)\s*  # for SWIG
              \s*\)/mx) do |var_name, in_module, class_name, parent|
      handle_class_module(var_name, "class", class_name, parent, in_module)
    end
  end

  def do_constants
    @content.scan(%r{\Wrb_define_
                   (
                      variable |
                      readonly_variable |
                      const |
                      global_const |
                    )
               \s*\(
                 (?:\s*(\w+),)?
                 \s*"(\w+)",
                 \s*(.*?)\s*\)\s*;
                 }xm) do |type, var_name, const_name, definition|
      var_name = "rb_cObject" if !var_name or var_name == "rb_mKernel"
      handle_constants(type, var_name, const_name, definition)
    end
  end

  ##
  # Look for includes of the form:
  #
  #   rb_include_module(rb_cArray, rb_mEnumerable);

  def do_includes
    @content.scan(/rb_include_module\s*\(\s*(\w+?),\s*(\w+?)\s*\)/) do |c,m|
      if cls = @classes[c]
        m = @known_classes[m] || m
        cls.add_include RDoc::Include.new(m, "")
      end
    end
  end

  def do_methods
    @content.scan(%r{rb_define_
                   (
                      singleton_method |
                      method           |
                      module_function  |
                      private_method
                   )
                   \s*\(\s*([\w\.]+),
                     \s*"([^"]+)",
                     \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\()?(\w+)\)?,
                     \s*(-?\w+)\s*\)
                   (?:;\s*/[*/]\s+in\s+(\w+?\.[cy]))?
                 }xm) do
      |type, var_name, meth_name, meth_body, param_count, source_file|

      # Ignore top-object and weird struct.c dynamic stuff
      next if var_name == "ruby_top_self"
      next if var_name == "nstr"
      next if var_name == "envtbl"
      next if var_name == "argf"   # it'd be nice to handle this one

      var_name = "rb_cObject" if var_name == "rb_mKernel"
      handle_method(type, var_name, meth_name,
                    meth_body, param_count, source_file)
    end

    @content.scan(%r{rb_define_attr\(
                             \s*([\w\.]+),
                             \s*"([^"]+)",
                             \s*(\d+),
                             \s*(\d+)\s*\);
                }xm) do |var_name, attr_name, attr_reader, attr_writer|
      #var_name = "rb_cObject" if var_name == "rb_mKernel"
      handle_attr(var_name, attr_name,
                  attr_reader.to_i != 0,
                  attr_writer.to_i != 0)
    end

    @content.scan(%r{rb_define_global_function\s*\(
                             \s*"([^"]+)",
                             \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\()?(\w+)\)?,
                             \s*(-?\w+)\s*\)
                (?:;\s*/[*/]\s+in\s+(\w+?\.[cy]))?
                }xm) do |meth_name, meth_body, param_count, source_file|
      handle_method("method", "rb_mKernel", meth_name,
                    meth_body, param_count, source_file)
    end

    @content.scan(/define_filetest_function\s*\(
                             \s*"([^"]+)",
                             \s*(?:RUBY_METHOD_FUNC\(|VALUEFUNC\()?(\w+)\)?,
                             \s*(-?\w+)\s*\)/xm) do
      |meth_name, meth_body, param_count|

      handle_method("method", "rb_mFileTest", meth_name, meth_body, param_count)
      handle_method("singleton_method", "rb_cFile", meth_name, meth_body, param_count)
    end
  end

  def find_attr_comment(attr_name)
    if @content =~ %r{((?>/\*.*?\*/\s+))
                   rb_define_attr\((?:\s*(\w+),)?\s*"#{attr_name}"\s*,.*?\)\s*;}xmi
      $1
    elsif @content =~ %r{Document-attr:\s#{attr_name}\s*?\n((?>.*?\*/))}m
      $1
    else
      ''
    end
  end

  ##
  # Find the C code corresponding to a Ruby method

  def find_body(class_name, meth_name, meth_obj, body, quiet = false)
    case body
    when %r"((?>/\*.*?\*/\s*))(?:(?:static|SWIGINTERN)\s+)?(?:intern\s+)?VALUE\s+#{meth_name}
            \s*(\([^)]*\))([^;]|$)"xm
      comment, params = $1, $2
      body_text = $&

      remove_private_comments(comment) if comment

      # see if we can find the whole body

      re = Regexp.escape(body_text) + '[^(]*^\{.*?^\}'
      body_text = $& if /#{re}/m =~ body

      # The comment block may have been overridden with a 'Document-method'
      # block. This happens in the interpreter when multiple methods are
      # vectored through to the same C method but those methods are logically
      # distinct (for example Kernel.hash and Kernel.object_id share the same
      # implementation

      override_comment = find_override_comment(class_name, meth_obj.name)
      comment = override_comment if override_comment

      find_modifiers(comment, meth_obj) if comment

#        meth_obj.params = params
      meth_obj.start_collecting_tokens
      meth_obj.add_token(RDoc::RubyToken::Token.new(1,1).set_text(body_text))
      meth_obj.comment = mangle_comment(comment)
    when %r{((?>/\*.*?\*/\s*))^\s*\#\s*define\s+#{meth_name}\s+(\w+)}m
      comment = $1
      find_body(class_name, $2, meth_obj, body, true)
      find_modifiers(comment, meth_obj)
      meth_obj.comment = mangle_comment(comment) + meth_obj.comment
    when %r{^\s*\#\s*define\s+#{meth_name}\s+(\w+)}m
      unless find_body(class_name, $1, meth_obj, body, true)
        warn "No definition for #{meth_name}" unless @options.quiet
        return false
      end
    else

      # No body, but might still have an override comment
      comment = find_override_comment(class_name, meth_obj.name)

      if comment
        find_modifiers(comment, meth_obj)
        meth_obj.comment = mangle_comment(comment)
      else
        warn "No definition for #{meth_name}" unless @options.quiet
        return false
      end
    end
    true
  end

  def find_class(raw_name, name)
    unless @classes[raw_name]
      if raw_name =~ /^rb_m/
        container = @top_level.add_module RDoc::NormalModule, name
      else
        container = @top_level.add_class RDoc::NormalClass, name, nil
      end

      container.record_location @top_level
      @classes[raw_name] = container
    end
    @classes[raw_name]
  end

  ##
  # Look for class or module documentation above Init_+class_name+(void),
  # in a Document-class +class_name+ (or module) comment or above an
  # rb_define_class (or module).  If a comment is supplied above a matching
  # Init_ and a rb_define_class the Init_ comment is used.
  #
  #   /*
  #    * This is a comment for Foo
  #    */
  #   Init_Foo(void) {
  #       VALUE cFoo = rb_define_class("Foo", rb_cObject);
  #   }
  #
  #   /*
  #    * Document-class: Foo
  #    * This is a comment for Foo
  #    */
  #   Init_foo(void) {
  #       VALUE cFoo = rb_define_class("Foo", rb_cObject);
  #   }
  #
  #   /*
  #    * This is a comment for Foo
  #    */
  #   VALUE cFoo = rb_define_class("Foo", rb_cObject);

  def find_class_comment(class_name, class_meth)
    comment = nil
    if @content =~ %r{((?>/\*.*?\*/\s+))
                   (static\s+)?void\s+Init_#{class_name}\s*(?:_\(\s*)?\(\s*(?:void\s*)\)}xmi then
      comment = $1
    elsif @content =~ %r{Document-(?:class|module):\s#{class_name}\s*?(?:<\s+[:,\w]+)?\n((?>.*?\*/))}m
      comment = $1
    else
      if @content =~ /rb_define_(class|module)/m then
        class_name = class_name.split("::").last
        comments = []
        @content.split(/(\/\*.*?\*\/)\s*?\n/m).each_with_index do |chunk, index|
          comments[index] = chunk
          if chunk =~ /rb_define_(class|module).*?"(#{class_name})"/m then
            comment = comments[index-1]
            break
          end
        end
      end
    end
    class_meth.comment = mangle_comment(comment) if comment
  end

  ##
  # Finds a comment matching +type+ and +const_name+ either above the
  # comment or in the matching Document- section.

  def find_const_comment(type, const_name)
    if @content =~ %r{((?>^\s*/\*.*?\*/\s+))
                   rb_define_#{type}\((?:\s*(\w+),)?\s*"#{const_name}"\s*,.*?\)\s*;}xmi
      $1
    elsif @content =~ %r{Document-(?:const|global|variable):\s#{const_name}\s*?\n((?>.*?\*/))}m
      $1
    else
      ''
    end
  end

  ##
  # If the comment block contains a section that looks like:
  #
  #    call-seq:
  #        Array.new
  #        Array.new(10)
  #
  # use it for the parameters.

  def find_modifiers(comment, meth_obj)
    if comment.sub!(/:nodoc:\s*^\s*\*?\s*$/m, '') or
       comment.sub!(/\A\/\*\s*:nodoc:\s*\*\/\Z/, '')
      meth_obj.document_self = false
    end
    if comment.sub!(/call-seq:(.*?)^\s*\*?\s*$/m, '') or
       comment.sub!(/\A\/\*\s*call-seq:(.*?)\*\/\Z/, '')
      seq = $1
      seq.gsub!(/^\s*\*\s*/, '')
      meth_obj.call_seq = seq
    end
  end

  def find_override_comment(class_name, meth_name)
    name = Regexp.escape(meth_name)
    if @content =~ %r{Document-method:\s+#{class_name}(?:\.|::|#)#{name}\s*?\n((?>.*?\*/))}m then
      $1
    elsif @content =~ %r{Document-method:\s#{name}\s*?\n((?>.*?\*/))}m then
      $1
    end
  end

  def handle_attr(var_name, attr_name, reader, writer)
    rw = ''
    if reader
      #@stats.num_methods += 1
      rw << 'R'
    end
    if writer
      #@stats.num_methods += 1
      rw << 'W'
    end

    class_name = @known_classes[var_name]

    return unless class_name

    class_obj  = find_class(var_name, class_name)

    if class_obj
      comment = find_attr_comment(attr_name)
      unless comment.empty?
        comment = mangle_comment(comment)
      end
      att = RDoc::Attr.new '', attr_name, rw, comment
      class_obj.add_attribute(att)
    end
  end

  def handle_class_module(var_name, class_mod, class_name, parent, in_module)
    parent_name = @known_classes[parent] || parent

    if in_module
      enclosure = @classes[in_module] || @@enclosure_classes[in_module]
      unless enclosure
        if enclosure = @known_classes[in_module]
          handle_class_module(in_module, (/^rb_m/ =~ in_module ? "module" : "class"),
                              enclosure, nil, nil)
          enclosure = @classes[in_module]
        end
      end
      unless enclosure
        warn("Enclosing class/module '#{in_module}' for " +
              "#{class_mod} #{class_name} not known")
        return
      end
    else
      enclosure = @top_level
    end

    if class_mod == "class" then
      full_name = enclosure.full_name.to_s + "::#{class_name}"
      if @content =~ %r{Document-class:\s+#{full_name}\s*<\s+([:,\w]+)} then
        parent_name = $1
      end
      cm = enclosure.add_class RDoc::NormalClass, class_name, parent_name
      @stats.add_class cm
    else
      cm = enclosure.add_module RDoc::NormalModule, class_name
      @stats.add_module cm
    end

    cm.record_location(enclosure.toplevel)

    find_class_comment(cm.full_name, cm)
    @classes[var_name] = cm
    @@enclosure_classes[var_name] = cm
    @known_classes[var_name] = cm.full_name
  end

  ##
  # Adds constant comments.  By providing some_value: at the start ofthe
  # comment you can override the C value of the comment to give a friendly
  # definition.
  #
  #   /* 300: The perfect score in bowling */
  #   rb_define_const(cFoo, "PERFECT", INT2FIX(300);
  #
  # Will override +INT2FIX(300)+ with the value +300+ in the output RDoc.
  # Values may include quotes and escaped colons (\:).

  def handle_constants(type, var_name, const_name, definition)
    #@stats.num_constants += 1
    class_name = @known_classes[var_name]

    return unless class_name

    class_obj  = find_class(var_name, class_name)

    unless class_obj
      warn("Enclosing class/module '#{const_name}' for not known")
      return
    end

    comment = find_const_comment(type, const_name)

    # In the case of rb_define_const, the definition and comment are in
    # "/* definition: comment */" form.  The literal ':' and '\' characters
    # can be escaped with a backslash.
    if type.downcase == 'const' then
       elements = mangle_comment(comment).split(':')
       if elements.nil? or elements.empty? then
          con = RDoc::Constant.new(const_name, definition,
                                   mangle_comment(comment))
       else
          new_definition = elements[0..-2].join(':')
          if new_definition.empty? then # Default to literal C definition
             new_definition = definition
          else
             new_definition.gsub!("\:", ":")
             new_definition.gsub!("\\", '\\')
          end
          new_definition.sub!(/\A(\s+)/, '')
          new_comment = $1.nil? ? elements.last : "#{$1}#{elements.last.lstrip}"
          con = RDoc::Constant.new(const_name, new_definition,
                                   mangle_comment(new_comment))
       end
    else
       con = RDoc::Constant.new const_name, definition, mangle_comment(comment)
    end

    class_obj.add_constant(con)
  end

  ##
  # Removes #ifdefs that would otherwise confuse us

  def handle_ifdefs_in(body)
    body.gsub(/^#ifdef HAVE_PROTOTYPES.*?#else.*?\n(.*?)#endif.*?\n/m, '\1')
  end

  def handle_method(type, var_name, meth_name, meth_body, param_count,
                    source_file = nil)
    class_name = @known_classes[var_name]

    return unless class_name

    class_obj = find_class var_name, class_name

    if class_obj then
      if meth_name == "initialize" then
        meth_name = "new"
        type = "singleton_method"
      end

      meth_obj = RDoc::AnyMethod.new '', meth_name
      meth_obj.singleton = %w[singleton_method module_function].include? type

      p_count = (Integer(param_count) rescue -1)

      if p_count < 0
        meth_obj.params = "(...)"
      elsif p_count == 0
        meth_obj.params = "()"
      else
        meth_obj.params = "(" + (1..p_count).map{|i| "p#{i}"}.join(", ") + ")"
      end

      if source_file then
        file_name = File.join(@file_dir, source_file)
        body = (@@known_bodies[source_file] ||= File.read(file_name))
      else
        body = @content
      end

      if find_body(class_name, meth_body, meth_obj, body) and meth_obj.document_self then
        class_obj.add_method meth_obj
        @stats.add_method meth_obj
      end
    end
  end

  def handle_tab_width(body)
    if /\t/ =~ body
      tab_width = @options.tab_width
      body.split(/\n/).map do |line|
        1 while line.gsub!(/\t+/) { ' ' * (tab_width*$&.length - $`.length % tab_width)}  && $~ #`
        line
      end .join("\n")
    else
      body
    end
  end

  ##
  # Remove the /*'s and leading asterisks from C comments

  def mangle_comment(comment)
    comment.sub!(%r{/\*+}) { " " * $&.length }
    comment.sub!(%r{\*+/}) { " " * $&.length }
    comment.gsub!(/^[ \t]*\*/m) { " " * $&.length }
    comment
  end

  ##
  # Removes lines that are commented out that might otherwise get picked up
  # when scanning for classes and methods

  def remove_commented_out_lines
    @content.gsub!(%r{//.*rb_define_}, '//')
  end

  def remove_private_comments(comment)
     comment.gsub!(/\/?\*--\n(.*?)\/?\*\+\+/m, '')
     comment.sub!(/\/?\*--\n.*/m, '')
  end

  ##
  # Extract the classes/modules and methods from a C file and return the
  # corresponding top-level object

  def scan
    remove_commented_out_lines
    do_classes
    do_constants
    do_methods
    do_includes
    do_aliases
    @top_level
  end

  def warn(msg)
    $stderr.puts
    $stderr.puts msg
    $stderr.flush
  end

end

