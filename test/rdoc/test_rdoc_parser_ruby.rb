# coding: utf-8

require 'stringio'
require 'tempfile'
require 'rubygems'
require 'minitest/autorun'

require 'rdoc/options'
require 'rdoc/parser/ruby'
require 'rdoc/stats'

class TestRDocParserRuby < MiniTest::Unit::TestCase

  def setup
    @tempfile = Tempfile.new self.class.name
    @filename = @tempfile.path

    # Some tests need two paths.
    @tempfile2 = Tempfile.new self.class.name
    @filename2 = @tempfile2.path

    util_top_level
    @options = RDoc::Options.new
    @options.quiet = true
    @stats = RDoc::Stats.new 0
  end

  def teardown
    @tempfile.close
    @tempfile2.close
  end

  def test_look_for_directives_in_attr
    util_parser ""

    comment = "# :attr: my_attr\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr: my_attr\n", comment

    comment = "# :attr_reader: my_method\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr_reader: my_method\n", comment

    comment = "# :attr_writer: my_method\n"

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr_writer: my_method\n", comment
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

  def test_parse_alias
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "alias :next= :bar"

    tk = @parser.get_tk

    alas = @parser.parse_alias klass, RDoc::Parser::Ruby::NORMAL, tk, 'comment'

    assert_equal 'bar',     alas.old_name
    assert_equal 'next=',   alas.new_name
    assert_equal klass,     alas.parent
    assert_equal 'comment', alas.comment
  end

  def test_parse_alias_meta
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "alias m.chop m"

    tk = @parser.get_tk

    alas = @parser.parse_alias klass, RDoc::Parser::Ruby::NORMAL, tk, 'comment'

    assert_nil alas
  end

  def test_parse_attr
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my attr\n"

    util_parser "attr :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 1, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'my attr', foo.comment
  end

  def test_parse_attr_accessor
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my attr\n"

    util_parser "attr_accessor :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my attr', foo.comment

    bar = klass.attributes.last
    assert_equal 'bar', bar.name
    assert_equal 'RW', bar.rw
    assert_equal 'my attr', bar.comment
  end

  def test_parse_attr_accessor_writer
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my attr\n"

    util_parser "attr_writer :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'W', foo.rw
    assert_equal "my attr", foo.comment

    bar = klass.attributes.last
    assert_equal 'bar', bar.name
    assert_equal 'W', bar.rw
    assert_equal "my attr", bar.comment
  end

  def test_parse_meta_attr
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr: \n# my method\n"

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal "my method", foo.comment
  end

  def test_parse_meta_attr_accessor
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr_accessor: \n# my method\n"

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my method', foo.comment
  end

  def test_parse_meta_attr_named
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr: foo\n# my method\n"

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 1, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my method', foo.comment
  end

  def test_parse_meta_attr_reader
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr_reader: \n# my method\n"

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'R', foo.rw
    assert_equal 'my method', foo.comment
  end

  def test_parse_meta_attr_writer
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr_writer: \n# my method\n"

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'W', foo.rw
    assert_equal "my method", foo.comment
  end

  def test_parse_class
    comment = "##\n# my method\n"

    util_parser 'class Foo; end'

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'my method', foo.comment
  end

  def test_parse_class_ghost_method
    util_parser <<-CLASS
class Foo
  ##
  # :method: blah
  # my method
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, ''

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    assert_equal 'Foo#blah', blah.full_name
  end

  def test_parse_class_nested_superclass
    foo = RDoc::NormalModule.new 'Foo'
    foo.parent = @top_level

    util_parser "class Bar < Super\nend"

    tk = @parser.get_tk

    @parser.parse_class foo, RDoc::Parser::Ruby::NORMAL, tk, ''

    bar = foo.classes.first
    assert_equal 'Super', bar.superclass
  end

  def test_parse_module
    comment = "##\n# my module\n"

    util_parser 'module Foo; end'

    tk = @parser.get_tk

    @parser.parse_module @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'my module', foo.comment
  end

  def test_parse_class_colon3
    code = <<-CODE
class A
  class ::B
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, ''

    assert_equal %w[A B],    RDoc::TopLevel.classes.map { |c| c.full_name }
  end

  def test_parse_class_single
    code = <<-CODE
class A
  class << B
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, ''

    assert_equal %w[A],    RDoc::TopLevel.classes.map { |c| c.full_name }
    assert_equal %w[A::B], RDoc::TopLevel.modules.map { |c| c.full_name }
  end

  def test_parse_class_mistaken_for_module
    # The code below is not strictly legal Ruby (Foo must have been defined
    # before Foo::Bar is encountered), but RDoc might encounter Foo::Bar
    # before Foo if they live in different files.

    code = <<-EOF
class Foo::Bar
end

module Foo::Baz
end

class Foo
end
    EOF

    util_parser code

    @parser.scan

    assert_equal %w[Foo::Baz], RDoc::TopLevel.modules_hash.keys
    assert_empty @top_level.modules

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    bar = foo.classes.first
    assert_equal 'Foo::Bar', bar.full_name

    baz = foo.modules.first
    assert_equal 'Foo::Baz', baz.full_name
  end

  def test_parse_class_definition_encountered_after_class_reference
    # The code below is not strictly legal Ruby (Foo must have been defined
    # before Foo.bar is encountered), but RDoc might encounter Foo.bar before
    # Foo if they live in different files.

    code = <<-EOF
def Foo.bar
end

class Foo < IO
end
    EOF

    util_parser code

    @parser.scan

    assert_empty RDoc::TopLevel.modules_hash
    # HACK why does it fail?
    #assert_empty @top_level.modules

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'IO', foo.superclass

    bar = foo.method_list.first
    assert_equal 'bar', bar.name
  end

  def test_parse_module_relative_to_top_level_namespace
    comment = <<-EOF
#
# Weirdly named module
#
EOF

    code = comment + <<-EOF
module ::Foo
  class Helper
  end
end
EOF

    util_parser code
    @parser.scan()

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'Weirdly named module', foo.comment

    helper = foo.classes.first
    assert_equal 'Foo::Helper', helper.full_name
  end

  def test_parse_comment_attr
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :attr: foo\n# my attr\n"

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo',     foo.name
    assert_equal 'RW',      foo.rw
    assert_equal 'my attr',   foo.comment

    assert_equal nil,       foo.viewer
    assert_equal true,      foo.document_children
    assert_equal true,      foo.document_self
    assert_equal false,     foo.done_documenting
    assert_equal false,     foo.force_documentation
    assert_equal klass,     foo.parent
    assert_equal :public,   foo.visibility
    assert_equal "\n",      foo.text
    assert_equal klass.current_section, foo.section
  end

  def test_parse_comment_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# :method: foo\n# my method\n"

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',     foo.name
    assert_equal 'my method',   foo.comment

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
      tk(:COMMENT, 1, 1, nil, "# File #{@top_level.absolute_name}, line 1"),
      RDoc::Parser::Ruby::NEWLINE_TOKEN,
      tk(:SPACE,   1, 1, nil, ''),
    ]

    assert_equal stream, foo.token_stream
  end

  def test_parse_constant_alias
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    cB = klass.add_class RDoc::NormalClass, 'B'

    util_parser "A = B"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, ''

    assert_equal cB, klass.find_module_named('A')
  end

  def test_parse_constant_alias_same_name
    foo = @top_level.add_class RDoc::NormalClass, 'Foo'
    top_bar = @top_level.add_class RDoc::NormalClass, 'Bar'
    bar = foo.add_class RDoc::NormalClass, 'Bar'

    assert RDoc::TopLevel.find_class_or_module('::Bar')

    util_parser "A = ::Bar"

    tk = @parser.get_tk

    @parser.parse_constant foo, tk, ''

    assert_equal top_bar, bar.find_module_named('A')
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
    assert_equal 'my method', foo.comment

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
      tk(:COMMENT,    1, 1,  nil, "# File #{@top_level.absolute_name}, line 1"),
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
    assert_equal 'my method', foo.comment
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
    assert_equal 'my method', foo.comment
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
    assert_equal 'my method', foo.comment
  end

  def test_parse_meta_method_string_name
    klass = RDoc::NormalClass.new 'Foo'
    comment = "##\n# my method\n"

    util_parser "add_my_method 'foo'"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal 'my method', foo.comment
  end

  def test_parse_meta_method_unknown
    klass = RDoc::NormalClass.new 'Foo'
    comment = "##\n# my method\n"

    util_parser "add_my_method ('foo')"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'unknown', foo.name
    assert_equal 'my method', foo.comment
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
    assert_equal 'my method',   foo.comment

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
      tk(:COMMENT,    1, 1,  nil, "# File #{@top_level.absolute_name}, line 1"),
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

  def test_parse_method_alias
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def m() alias a b; end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, ''

    assert klass.aliases.empty?
  end

  def test_parse_method_utf8
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    method = "def ω() end"

    assert_equal Encoding::UTF_8, method.encoding if defined? ::Encoding

    util_parser method

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    omega = klass.method_list.first
    assert_equal "def \317\211", omega.text
  end

  def test_parse_method_funky
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "def (blah).foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert klass.method_list.empty?
  end

  def test_parse_method_internal_ivar
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo() def @blah.bar() end end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, ''

    assert_equal 1, klass.method_list.length
  end

  def test_parse_method_internal_lvar
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo() def blah.bar() end end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, ''

    assert_equal 1, klass.method_list.length
  end

  def test_parse_method_no_parens
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "def foo arg1, arg2\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2)', foo.params
  end

  def test_parse_method_parameters_comment
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "def foo arg1, arg2 # some useful comment\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2)', foo.params
  end

  def test_parse_method_parameters_comment_continue
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = "##\n# my method\n"

    util_parser "def foo arg1, arg2, # some useful comment\narg3\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2, arg3)', foo.params
  end

  def test_parse_method_toplevel
    klass = @top_level

    comment = "##\n# my method\n"

    util_parser "def foo arg1, arg2\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    object = RDoc::TopLevel.find_class_named 'Object'

    foo = object.method_list.first
    assert_equal 'Object#foo', foo.full_name
  end

  def test_parse_method_toplevel_class
    klass = @top_level

    util_parser "def Object.foo arg1, arg2\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, ''

    object = RDoc::TopLevel.find_class_named 'Object'

    foo = object.method_list.first
    assert_equal 'Object::foo', foo.full_name
  end

  def test_parse_statements_class_if
    comment = "##\n# my method\n"

    util_parser <<-CODE
module Foo
  X = if TRUE then
        ''
      end

  def blah
  end
end
    CODE

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name, 'module Foo'

    methods = foo.method_list
    assert_equal 1, methods.length
    assert_equal 'Foo#blah', methods.first.full_name
  end

  def test_parse_statements_class_nested
    comment = "##\n# my method\n"

    util_parser "module Foo\n#{comment}class Bar\nend\nend"

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name, 'module Foo'

    bar = foo.classes.first
    assert_equal 'Foo::Bar', bar.full_name, 'class Foo::Bar'
    assert_equal 'my method', bar.comment
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

    foo = @top_level.classes.first.method_list[0]
    assert_equal 'foo', foo.name

    foo2 = @top_level.classes.first.method_list.last
    assert_equal 'foo2', foo2.name
    assert_equal 'foo', foo2.is_alias_for.name
    assert @top_level.classes.first.aliases.empty?
  end

  def test_parse_statements_identifier_alias_method_before_original_method
    # This is not strictly legal Ruby code, but it simulates finding an alias
    # for a method before finding the original method, which might happen
    # to rdoc if the alias is in a different file than the original method
    # and rdoc processes the alias' file first.
    content = <<-EOF
class Foo
  alias_method :foo2, :foo

  alias_method :foo3, :foo

  def foo()
  end

  alias_method :foo4, :foo

  alias_method :foo5, :unknown
end
EOF

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    foo = @top_level.classes.first.method_list[0]
    assert_equal 'foo', foo.name

    foo2 = @top_level.classes.first.method_list[1]
    assert_equal 'foo2', foo2.name
    assert_equal 'foo', foo2.is_alias_for.name

    foo3 = @top_level.classes.first.method_list[2]
    assert_equal 'foo3', foo3.name
    assert_equal 'foo', foo3.is_alias_for.name

    foo4 = @top_level.classes.first.method_list.last
    assert_equal 'foo4', foo4.name
    assert_equal 'foo', foo4.is_alias_for.name

    assert_equal 'unknown', @top_level.classes.first.aliases[0].old_name
  end

  def test_parse_statements_identifier_constant
    content = <<-EOF
class Foo
  FIRST_CONSTANT = 5

  SECOND_CONSTANT = [
     1,
     2,
     3
  ]

  THIRD_CONSTANT = {
     :foo => 'bar',
     :x => 'y'
  }

  FOURTH_CONSTANT = SECOND_CONSTANT.map do |element|
    element + 1
    element + 2
  end

  FIFTH_CONSTANT = SECOND_CONSTANT.map { |element| element + 1 }
end
EOF

    util_parser content

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    constants = @top_level.classes.first.constants

    constant = constants[0]
    assert_equal 'FIRST_CONSTANT', constant.name
    assert_equal '5', constant.value

    constant = constants[1]
    assert_equal 'SECOND_CONSTANT', constant.name
    assert_equal '[      1,      2,      3   ]', constant.value

    constant = constants[2]
    assert_equal 'THIRD_CONSTANT', constant.name
    assert_equal "{      :foo => 'bar',      :x => 'y'   }", constant.value

    constant = constants[3]
    assert_equal 'FOURTH_CONSTANT', constant.name
    assert_equal 'SECOND_CONSTANT.map do |element|     element + 1     element + 2   end', constant.value

    constant = constants.last
    assert_equal 'FIFTH_CONSTANT', constant.name
    assert_equal 'SECOND_CONSTANT.map { |element| element + 1 }', constant.value
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

  def test_parse_statements_while_begin
    util_parser <<-RUBY
class A
  def a
    while begin a; b end
    end
  end

  def b
  end
end
    RUBY

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil, ''

    c_a = @top_level.classes.first
    assert_equal 'A', c_a.full_name

    assert_equal 1, @top_level.classes.length

    m_a = c_a.method_list.first
    m_b = c_a.method_list.last

    assert_equal 'A#a', m_a.full_name
    assert_equal 'A#b', m_b.full_name
  end

  def test_parse_top_level_statements_alias_method
    content = <<-CONTENT
class A
  alias_method :a, :[] unless c
end

B = A

class C
end
    CONTENT

    util_parser content

    @parser.parse_statements @top_level
  end

  def test_sanity_integer
    util_parser '1'
    assert_equal '1', @parser.get_tk.text

    util_parser '1.0'
    assert_equal '1.0', @parser.get_tk.text
  end

  def test_sanity_interpolation
    last_tk = nil
    util_parser 'class A; B = "#{c}"; end'

    while tk = @parser.get_tk do last_tk = tk end

    assert_equal "\n", last_tk.text
  end

  # If you're writing code like this you're doing it wrong

  def test_sanity_interpolation_crazy
    last_tk = nil
    util_parser '"#{"#{"a")}" if b}"'

    assert_equal '"#{"#{"a")}" if b}"', @parser.get_tk.text
    assert_equal RDoc::RubyToken::TkNL, @parser.get_tk.class
  end

  def test_sanity_interpolation_curly
    last_tk = nil
    util_parser '%{ #{} }'

    assert_equal '%{ #{} }', @parser.get_tk.text
    assert_equal RDoc::RubyToken::TkNL, @parser.get_tk.class
  end

  def test_sanity_interpolation_format
    util_parser '"#{stftime("%m-%d")}"'

    while tk = @parser.get_tk do end
  end

  def test_sanity_symbol_interpolation
    util_parser ':"#{bar}="'

    while tk = @parser.get_tk do end
  end

  def tk(klass, line, char, name, text)
    klass = RDoc::RubyToken.const_get "Tk#{klass.to_s.upcase}"

    token = if klass.instance_method(:initialize).arity == 3 then
              raise ArgumentError, "name not used for #{klass}" unless name.nil?
              klass.new nil, line, char
            else
              klass.new nil, line, char, name
            end

    token.set_text text

    token
  end

  def util_parser(content)
    @parser = RDoc::Parser::Ruby.new @top_level, @filename, content, @options,
                                     @stats
  end

  def util_two_parsers(first_file_content, second_file_content)
    util_parser first_file_content

    @parser2 = RDoc::Parser::Ruby.new @top_level2, @filename,
                                      second_file_content, @options, @stats
  end

  def util_top_level
    RDoc::TopLevel.reset
    @top_level = RDoc::TopLevel.new @filename
    @top_level2 = RDoc::TopLevel.new @filename2
  end

end

