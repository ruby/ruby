require 'stringio'
require 'tempfile'
require 'test/unit'

require 'rdoc/options'
require 'rdoc/parser/ruby'
require 'rdoc/stats'

class TestRdocParserRuby < Test::Unit::TestCase

  def setup
    @tempfile = Tempfile.new self.class.name
    @filename = @tempfile.path

    util_toplevel
    @options = RDoc::Options.new Hash.new
    @options.quiet = true
    @stats = RDoc::Stats.new

    @progress = StringIO.new
  end

  def teardown
    @tempfile.unlink
  end

  def test_look_for_directives_in_commented
    util_parser ""

    comment = "# how to make a section:\n# # :section: new section\n"

    @parser.look_for_directives_in @top_level, comment

    section = @top_level.current_section
    assert_equal nil, section.title
    assert_equal nil, section.comment

    assert_equal "# how to make a section:\n# # :section: new section\n",
                 comment
  end

  def test_look_for_directives_in_enddoc
    util_parser ""

    assert_throws :enddoc do
      @parser.look_for_directives_in @top_level, "# :enddoc:\n"
    end
  end

  def test_look_for_directives_in_main
    util_parser ""

    @parser.look_for_directives_in @top_level, "# :main: new main page\n"

    assert_equal 'new main page', @options.main_page
  end

  def test_look_for_directives_in_method
    util_parser ""

    comment = "# :method: my_method\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :method: my_method\n", comment

    comment = "# :singleton-method: my_method\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :singleton-method: my_method\n", comment
  end

  def test_look_for_directives_in_startdoc
    util_parser ""

    @top_level.stop_doc
    assert !@top_level.document_self
    assert !@top_level.document_children
    assert !@top_level.force_documentation

    @parser.look_for_directives_in @top_level, "# :startdoc:\n"

    assert @top_level.document_self
    assert @top_level.document_children
    assert @top_level.force_documentation
  end

  def test_look_for_directives_in_stopdoc
    util_parser ""

    assert @top_level.document_self
    assert @top_level.document_children

    @parser.look_for_directives_in @top_level, "# :stopdoc:\n"

    assert !@top_level.document_self
    assert !@top_level.document_children
  end

  def test_look_for_directives_in_section
    util_parser ""

    comment = "# :section: new section\n# woo stuff\n"

    @parser.look_for_directives_in @top_level, comment

    section = @top_level.current_section
    assert_equal 'new section', section.title
    assert_equal "# woo stuff\n", section.comment

    assert_equal '', comment
  end

  def test_look_for_directives_in_title
    util_parser ""

    @parser.look_for_directives_in @top_level, "# :title: new title\n"

    assert_equal 'new title', @options.title
  end

  def test_look_for_directives_in_unhandled
    util_parser ""

    comment = "# :unhandled: \n# :title: hi\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :unhandled: \n", comment

    assert_equal 'hi', @options.title
  end

  def test_parse_meta_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal comment, foo.comment

    assert_equal [],      foo.aliases
    assert_equal nil,     foo.block_params
    assert_equal nil,     foo.call_seq
    assert_equal true,    foo.document_children
    assert_equal true,    foo.document_self
    assert_equal false,   foo.done_documenting
    assert_equal false,   foo.dont_rename_initialize
    assert_equal false,   foo.force_documentation
    assert_equal nil,     foo.is_alias_for
    assert_equal '',      foo.params
    assert_equal klass,   foo.parent
    assert_equal false,   foo.singleton
    assert_equal 'add_my_method :foo', foo.text
    assert_equal nil,     foo.viewer
    assert_equal :public, foo.visibility
    assert_equal klass.current_section, foo.section

    stream = [
      tk(:COMMENT, 1, 1, nil, "# File #{@top_level.file_absolute_name}, line 1"),
      RDoc::Parser::Ruby::NEWLINE_TOKEN,
      tk(:SPACE,      1, 1,  nil, ''),
      tk(:IDENTIFIER, 1, 0,  'add_my_method', 'add_my_method'),
      tk(:SPACE,      1, 13, nil, ' '),
      tk(:SYMBOL,     1, 14, nil, ':foo'),
      tk(:COMMA,      1, 18, nil, ','),
      tk(:SPACE,      1, 19, nil, ' '),
      tk(:SYMBOL,     1, 20, nil, ':bar'),
      tk(:NL,         1, 24, nil, "\n"),
    ]

    assert_equal stream, foo.token_stream
  end

  def test_parse_meta_method_name
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :method: woo_hoo!\n# my method\n"

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'woo_hoo!', foo.name
    assert_equal "##\n# my method\n", foo.comment
  end

  def test_parse_meta_method_singleton
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :singleton-method:\n# my method\n"

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal true, foo.singleton, 'singleton method'
    assert_equal "##\n# my method\n", foo.comment
  end

  def test_parse_meta_method_singleton_name
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :singleton-method: woo_hoo!\n# my method\n"

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'woo_hoo!', foo.name
    assert_equal true, foo.singleton, 'singleton method'
    assert_equal "##\n# my method\n", foo.comment
  end

  def test_parse_meta_method_string_name
    klass = RDoc::NormalClass.new 'Foo'
    comment = "##\n# my method\n"

    util_parser "add_my_method 'foo'"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal comment, foo.comment
  end

  def test_parse_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "def foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',     foo.name
    assert_equal comment,   foo.comment

    assert_equal [],        foo.aliases
    assert_equal nil,       foo.block_params
    assert_equal nil,       foo.call_seq
    assert_equal nil,       foo.is_alias_for
    assert_equal nil,       foo.viewer
    assert_equal true,      foo.document_children
    assert_equal true,      foo.document_self
    assert_equal '()',      foo.params
    assert_equal false,     foo.done_documenting
    assert_equal false,     foo.dont_rename_initialize
    assert_equal false,     foo.force_documentation
    assert_equal klass,     foo.parent
    assert_equal false,     foo.singleton
    assert_equal :public,   foo.visibility
    assert_equal 'def foo', foo.text
    assert_equal klass.current_section, foo.section

    stream = [
      tk(:COMMENT, 1, 1, nil, "# File #{@top_level.file_absolute_name}, line 1"),
      RDoc::Parser::Ruby::NEWLINE_TOKEN,
      tk(:SPACE,      1, 1,  nil,   ''),
      tk(:DEF,        1, 0,  'def', 'def'),
      tk(:SPACE,      1, 3,  nil,   ' '),
      tk(:IDENTIFIER, 1, 4,  'foo', 'foo'),
      tk(:LPAREN,     1, 7,  nil,   '('),
      tk(:RPAREN,     1, 8,  nil,   ')'),
      tk(:SPACE,      1, 9,  nil,   ' '),
      tk(:COLON,      1, 10, nil,   ':'),
      tk(:IDENTIFIER, 1, 11, 'bar', 'bar'),
      tk(:SPACE,      1, 14, nil,   ' '),
      tk(:END,        1, 15, 'end', 'end'),
    ]

    assert_equal stream, foo.token_stream
  end

  def test_parse_statements_comment
    content = <<-EOF
class Foo
  ##
  # :method: my_method
  # my method comment

end
    EOF
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :method: foo\n# my method\n"

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',     foo.name
    assert_equal comment,   foo.comment

    assert_equal [],        foo.aliases
    assert_equal nil,       foo.block_params
    assert_equal nil,       foo.call_seq
    assert_equal nil,       foo.is_alias_for
    assert_equal nil,       foo.viewer
    assert_equal true,      foo.document_children
    assert_equal true,      foo.document_self
    assert_equal '',        foo.params
    assert_equal false,     foo.done_documenting
    assert_equal false,     foo.dont_rename_initialize
    assert_equal false,     foo.force_documentation
    assert_equal klass,     foo.parent
    assert_equal false,     foo.singleton
    assert_equal :public,   foo.visibility
    assert_equal "\n",      foo.text
    assert_equal klass.current_section, foo.section

    stream = [
      tk(:COMMENT, 1, 1, nil, "# File #{@top_level.file_absolute_name}, line 1"),
      RDoc::Parser::Ruby::NEWLINE_TOKEN,
      tk(:SPACE,      1, 1,  nil,   ''),
    ]

    assert_equal stream, foo.token_stream
  end

  def test_parse_statements_identifier_meta_method
    content = <<-EOF
class Foo
  ##
  # this is my method
  add_my_method :foo
end
    EOF

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
  end

  def test_parse_statements_identifier_alias_method
    content = "class Foo def foo() end; alias_method :foo2, :foo end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo2 = @top_level.classes.first.method_list.last
    assert_equal 'foo2', foo2.name
    assert_equal 'foo', foo2.is_alias_for.name
  end

  def test_parse_statements_identifier_attr
    content = "class Foo; attr :foo; end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'R', foo.rw
  end

  def test_parse_statements_identifier_attr_accessor
    content = "class Foo; attr_accessor :foo; end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
  end

  def test_parse_statements_identifier_extra_accessors
    @options.extra_accessors = /^my_accessor$/

    content = "class Foo; my_accessor :foo; end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.attributes.first
    assert_equal 'foo', foo.name
    assert_equal '?', foo.rw
  end

  def test_parse_statements_identifier_include
    content = "class Foo; include Bar; end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.name
    assert_equal 1, foo.includes.length
  end

  def test_parse_statements_identifier_module_function
    content = "module Foo def foo() end; module_function :foo; end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo, s_foo = @top_level.modules.first.method_list
    assert_equal 'foo', foo.name, 'instance method name'
    assert_equal :private, foo.visibility, 'instance method visibility'
    assert_equal false, foo.singleton, 'instance method singleton'

    assert_equal 'foo', s_foo.name, 'module function name'
    assert_equal :public, s_foo.visibility, 'module function visibility'
    assert_equal true, s_foo.singleton, 'module function singleton'
  end

  def test_parse_statements_identifier_private
    content = "class Foo private; def foo() end end"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
    assert_equal :private, foo.visibility
  end

  def test_parse_statements_identifier_require
    content = "require 'bar'"

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    assert_equal 1, @top_level.requires.length
  end

  def tk(klass, line, char, name, text)
    klass = RDoc::RubyToken.const_get "Tk#{klass.to_s.upcase}"

    token = if klass.instance_method(:initialize).arity == 2 then
              raise ArgumentError, "name not used for #{klass}" unless name.nil?
              klass.new line, char
            else
              klass.new line, char, name
            end

    token.set_text text

    token
  end

  def util_parser(content)
    @parser = RDoc::Parser::Ruby.new @top_level, @filename, content, @options,
                                     @stats
    @parser.progress = @progress
    @parser
  end

  def util_toplevel
    RDoc::TopLevel.reset
    @top_level = RDoc::TopLevel.new @filename
  end

end

