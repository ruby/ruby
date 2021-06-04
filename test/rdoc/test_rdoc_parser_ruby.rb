# frozen_string_literal: true

require_relative 'helper'

class TestRDocParserRuby < RDoc::TestCase

  def setup
    super

    @tempfile = Tempfile.new self.class.name
    @filename = @tempfile.path

    # Some tests need two paths.
    @tempfile2 = Tempfile.new self.class.name
    @filename2 = @tempfile2.path

    @top_level = @store.add_file @filename
    @top_level2 = @store.add_file @filename2

    @options = RDoc::Options.new
    @options.quiet = true
    @options.option_parser = OptionParser.new

    @comment = RDoc::Comment.new '', @top_level

    @stats = RDoc::Stats.new @store, 0
  end

  def teardown
    super

    @tempfile.close!
    @tempfile2.close!
  end

  def test_collect_first_comment
    p = util_parser <<-CONTENT
# first

# second
class C; end
    CONTENT

    comment = p.collect_first_comment

    assert_equal RDoc::Comment.new("# first\n", @top_level), comment
  end

  def test_collect_first_comment_encoding
    @options.encoding = Encoding::CP852

    p = util_parser <<-CONTENT
# first

# second
class C; end
    CONTENT

    comment = p.collect_first_comment

    assert_equal Encoding::CP852, comment.text.encoding
  end

  def test_collect_first_comment_rd_hash
    parser = util_parser <<-CONTENT
=begin
first
=end

# second
class C; end
    CONTENT

    comment = parser.collect_first_comment

    assert_equal RDoc::Comment.new("first\n", @top_level), comment
  end

  def test_get_class_or_module
    ctxt = RDoc::Context.new
    ctxt.store = @store

    cont, name_t, given_name = util_parser('A')    .get_class_or_module ctxt

    assert_equal ctxt, cont
    assert_equal 'A', name_t[:text]
    assert_equal 'A', given_name

    cont, name_t, given_name = util_parser('B::C') .get_class_or_module ctxt

    b = @store.find_module_named('B')
    assert_equal b, cont
    assert_equal [@top_level], b.in_files
    assert_equal 'C', name_t[:text]
    assert_equal 'B::C', given_name

    cont, name_t, given_name = util_parser('D:: E').get_class_or_module ctxt

    assert_equal @store.find_module_named('D'), cont
    assert_equal 'E', name_t[:text]
    assert_equal 'D::E', given_name

    assert_nothing_raised do
      util_parser("A::\nB").get_class_or_module ctxt
    end
  end

  def test_get_class_or_module_document_children
    ctxt = @top_level.add_class RDoc::NormalClass, 'A'
    ctxt.stop_doc

    util_parser('B::C').get_class_or_module ctxt

    b = @store.find_module_named('A::B')
    assert b.ignored?

    d = @top_level.add_class RDoc::NormalClass, 'A::D'

    util_parser('D::E').get_class_or_module ctxt

    refute d.ignored?
  end

  def test_get_class_or_module_ignore_constants
    ctxt = RDoc::Context.new
    ctxt.store = @store

    util_parser('A')   .get_class_or_module ctxt, true
    util_parser('A::B').get_class_or_module ctxt, true

    assert_empty ctxt.constants
    assert_empty @store.modules_hash.keys
    assert_empty @store.classes_hash.keys
  end

  def test_get_class_specification
    assert_equal 'A',    util_parser('A')   .get_class_specification
    assert_equal 'A::B', util_parser('A::B').get_class_specification
    assert_equal '::A',  util_parser('::A').get_class_specification

    assert_equal 'self', util_parser('self').get_class_specification

    assert_equal '',     util_parser('').get_class_specification

    assert_equal '',     util_parser('$g').get_class_specification
  end

  def test_get_symbol_or_name
    util_parser "* & | + 5 / 4"

    assert_equal '*', @parser.get_symbol_or_name

    @parser.skip_tkspace

    assert_equal '&', @parser.get_symbol_or_name

    @parser.skip_tkspace

    assert_equal '|', @parser.get_symbol_or_name

    @parser.skip_tkspace

    assert_equal '+', @parser.get_symbol_or_name

    @parser.skip_tkspace
    @parser.get_tk
    @parser.skip_tkspace

    assert_equal '/', @parser.get_symbol_or_name
  end

  def test_suppress_parents
    a = @top_level.add_class RDoc::NormalClass, 'A'
    b = a.add_class RDoc::NormalClass, 'B'
    c = b.add_class RDoc::NormalClass, 'C'

    util_parser ''

    @parser.suppress_parents c, a

    assert c.suppressed?
    assert b.suppressed?
    refute a.suppressed?
  end

  def test_suppress_parents_documented
    a = @top_level.add_class RDoc::NormalClass, 'A'
    b = a.add_class RDoc::NormalClass, 'B'
    b.add_comment RDoc::Comment.new("hello"), @top_level
    c = b.add_class RDoc::NormalClass, 'C'

    util_parser ''

    @parser.suppress_parents c, a

    assert c.suppressed?
    refute b.suppressed?
    refute a.suppressed?
  end

  def test_look_for_directives_in_attr
    util_parser ""

    comment = RDoc::Comment.new "# :attr: my_attr\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr: my_attr\n", comment.text

    comment = RDoc::Comment.new "# :attr_reader: my_method\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr_reader: my_method\n", comment.text

    comment = RDoc::Comment.new "# :attr_writer: my_method\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :attr_writer: my_method\n", comment.text
  end

  def test_look_for_directives_in_commented
    util_parser ""

    comment = RDoc::Comment.new <<-COMMENT, @top_level
# how to make a section:
# # :section: new section
    COMMENT

    @parser.look_for_directives_in @top_level, comment

    section = @top_level.current_section
    assert_nil   section.title
    assert_nil   section.comment

    assert_equal "# how to make a section:\n# # :section: new section\n",
                 comment.text
  end

  def test_look_for_directives_in_method
    util_parser ""

    comment = RDoc::Comment.new "# :method: my_method\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :method: my_method\n", comment.text

    comment = RDoc::Comment.new "# :singleton-method: my_method\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal "# :singleton-method: my_method\n", comment.text
  end

  def test_look_for_directives_in_section
    util_parser ""

    comment = RDoc::Comment.new <<-COMMENT, @top_level
# :section: new section
# woo stuff
    COMMENT

    @parser.look_for_directives_in @top_level, comment

    section = @top_level.current_section
    assert_equal 'new section', section.title
    assert_equal [comment("# woo stuff\n", @top_level)], section.comments

    assert_empty comment
  end

  def test_look_for_directives_in_unhandled
    util_parser ""

    comment = RDoc::Comment.new "# :unhandled: blah\n", @top_level

    @parser.look_for_directives_in @top_level, comment

    assert_equal 'blah', @top_level.metadata['unhandled']
  end

  def test_parse_for_in
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new '', @top_level

    util_parser <<ruby
def sum(n)
  result = 0
  for i in 1..n do
    result += i
  end
  result
end
ruby

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    sum = klass.method_list.first
    assert_equal 'sum',      sum.name
    assert_equal @top_level, sum.file
  end

  def test_parse_on_ignored_nl_with_nil_text
    util_parser <<ruby
class Foo
  def meth
    variable # comment
      .chain
  end
end
ruby

    expected = <<EXPECTED
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">meth</span>
  <span class="ruby-identifier">variable</span> <span class="ruby-comment"># comment</span>
    .<span class="ruby-identifier">chain</span>
<span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @store.find_class_named 'Foo'
    meth = foo.method_list.first

    assert_equal 'meth',     meth.name
    assert_equal @top_level, meth.file

    markup_code = meth.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_redefined_op_with_constant
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new '', @top_level

    util_parser <<ruby
def meth
  Integer::**()
  return Integer::**()
  break Integer::**()
  case Integer::**()
  when Integer::**()
  end
  while Integer::**()
  end
  yield Integer::**()
  defined? Integer::**()
  if Integer::**()
  end
end
ruby

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    meth = klass.method_list.first
    assert_equal 'meth',     meth.name
  end

  def test_parse_alias
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "alias :next= :bar"

    tk = @parser.get_tk

    alas = @parser.parse_alias klass, RDoc::Parser::Ruby::NORMAL, tk, 'comment'

    assert_equal 'bar',      alas.old_name
    assert_equal 'next=',    alas.new_name
    assert_equal klass,      alas.parent
    assert_equal 'comment',  alas.comment
    assert_equal @top_level, alas.file
    assert_equal 1,          alas.line
  end

  def test_parse_alias_singleton
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "alias :next= :bar"

    tk = @parser.get_tk

    alas = @parser.parse_alias klass, RDoc::Parser::Ruby::SINGLE, tk, 'comment'

    assert_equal 'bar',      alas.old_name
    assert_equal 'next=',    alas.new_name
    assert_equal klass,      alas.parent
    assert_equal 'comment',  alas.comment
    assert_equal @top_level, alas.file
    assert                   alas.singleton
  end

  def test_parse_alias_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    util_parser "alias :next= :bar"

    tk = @parser.get_tk

    @parser.parse_alias klass, RDoc::Parser::Ruby::NORMAL, tk, 'comment'

    assert_empty klass.aliases
    assert_empty klass.unmatched_alias_lists
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

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level, :ruby

    util_parser "attr :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 1, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'my attr', foo.comment.text
    assert_equal @top_level, foo.file
    assert_equal 1, foo.line
  end

  def test_parse_attr_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level

    util_parser "attr :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty klass.attributes
  end

  def test_parse_attr_accessor
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level, :ruby

    util_parser "attr_accessor :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my attr', foo.comment.text
    assert_equal @top_level, foo.file
    assert_equal 1, foo.line

    bar = klass.attributes.last
    assert_equal 'bar', bar.name
    assert_equal 'RW', bar.rw
    assert_equal 'my attr', bar.comment.text
  end

  def test_parse_attr_accessor_with_newline
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level, :ruby

    util_parser "attr_accessor :foo, :bar,\n  :baz,\n  :qux"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 4, klass.attributes.length

    foo = klass.attributes[0]
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my attr', foo.comment.text
    assert_equal @top_level, foo.file
    assert_equal 1, foo.line

    bar = klass.attributes[1]
    assert_equal 'bar', bar.name
    assert_equal 'RW', bar.rw
    assert_equal 'my attr', bar.comment.text

    bar = klass.attributes[2]
    assert_equal 'baz', bar.name
    assert_equal 'RW', bar.rw
    assert_equal 'my attr', bar.comment.text

    bar = klass.attributes[3]
    assert_equal 'qux', bar.name
    assert_equal 'RW', bar.rw
    assert_equal 'my attr', bar.comment.text
  end

  def test_parse_attr_accessor_nodoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level

    util_parser "attr_accessor :foo, :bar # :nodoc:"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 0, klass.attributes.length
  end

  def test_parse_attr_accessor_nodoc_track
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level

    @options.visibility = :nodoc

    util_parser "attr_accessor :foo, :bar # :nodoc:"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    refute_empty klass.attributes
  end

  def test_parse_attr_accessor_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level

    util_parser "attr_accessor :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty klass.attributes
  end

  def test_parse_attr_accessor_writer
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my attr\n", @top_level, :ruby

    util_parser "attr_writer :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_attr_accessor klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'W', foo.rw
    assert_equal "my attr", foo.comment.text
    assert_equal @top_level, foo.file

    bar = klass.attributes.last
    assert_equal 'bar', bar.name
    assert_equal 'W', bar.rw
    assert_equal "my attr", bar.comment.text
  end

  def test_parse_meta_attr
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# :attr: \n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal "my method", foo.comment.text
    assert_equal @top_level, foo.file
  end

  def test_parse_meta_attr_accessor
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :attr_accessor: \n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 2, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level, foo.file
  end

  def test_parse_meta_attr_named
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# :attr: foo\n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_equal 1, klass.attributes.length
    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level, foo.file
  end

  def test_parse_meta_attr_reader
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :attr_reader: \n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'R', foo.rw
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level, foo.file
  end

  def test_parse_meta_attr_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# :attr: \n# my method\n", @top_level

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty klass.attributes
  end

  def test_parse_meta_attr_writer
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :attr_writer: \n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar"

    tk = @parser.get_tk

    @parser.parse_meta_attr klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'W', foo.rw
    assert_equal "my method", foo.comment.text
    assert_equal @top_level, foo.file
  end

  def test_parse_class
    comment = RDoc::Comment.new "##\n# my class\n", @top_level, :ruby

    util_parser "class Foo\nend"

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'my class', foo.comment.text
    assert_equal [@top_level], foo.in_files
    assert_equal 1, foo.line
  end

  def test_parse_class_singleton
    comment = RDoc::Comment.new "##\n# my class\n", @top_level

    util_parser <<-RUBY
class C
  class << self
  end
end
    RUBY

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    c = @top_level.classes.first
    assert_equal 'C', c.full_name
    assert_equal 1, c.line
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

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    assert_equal 'Foo#blah', blah.full_name
    assert_equal 3, blah.line
    assert_equal @top_level, blah.file
  end

  def test_parse_class_in_a_file_repeatedly
    @filename = 'a.rb'
    comment_a = RDoc::Comment.new "# aaa\n", @top_level
    util_parser "class Foo\nend"
    tk = @parser.get_tk
    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment_a
    comment_b = RDoc::Comment.new "# bbb\n", @top_level
    util_parser "class Foo\nend"
    tk = @parser.get_tk
    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment_b

    @filename = 'b.rb'
    comment_c = RDoc::Comment.new "# ccc\n", @top_level
    util_parser "class Foo\nend"
    tk = @parser.get_tk
    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment_c

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_equal [[comment_a, @top_level],
                  [comment_b, @top_level],
                  [comment_c, @top_level]], foo.comment_location
    assert_equal [@top_level], foo.in_files
    assert_equal 1, foo.line
  end

  def test_parse_class_ghost_method_yields
    util_parser <<-CLASS
class Foo
  ##
  # :method:
  # :call-seq:
  #   yields(name)
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    assert_equal 'Foo#yields', blah.full_name
    assert_equal 'yields(name)', blah.call_seq
    assert_equal 3, blah.line
    assert_equal @top_level, blah.file
  end

  def test_parse_call_syntax_sugar_for_constant
    util_parser <<-CODE
Foo = proc{}
Foo::()
    CODE

    assert_nothing_raised do
      @parser.scan
    end
  end

  def test_parse_class_multi_ghost_methods
    util_parser <<-'CLASS'
class Foo
  ##
  # :method: one
  #
  # my method

  ##
  # :method: two
  #
  # my method

  [:one, :two].each do |t|
    eval("def #{t}; \"#{t}\"; end")
  end
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    assert_equal 2, foo.method_list.length
  end

  def test_parse_class_nodoc
    comment = RDoc::Comment.new "##\n# my class\n", @top_level

    util_parser "class Foo # :nodoc:\nend"

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_empty foo.comment
    assert_equal [@top_level], foo.in_files
    assert_equal 1, foo.line
  end

  def test_parse_class_single_root
    comment = RDoc::Comment.new "##\n# my class\n", @top_level

    util_parser "class << ::Foo\nend"

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @store.all_modules.first
    assert_equal 'Foo', foo.full_name
  end

  def test_parse_class_stopdoc
    @top_level.stop_doc

    comment = RDoc::Comment.new "##\n# my class\n", @top_level

    util_parser "class Foo\nend"

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty @top_level.classes.first.comment
  end

  def test_parse_class_lower_name_warning
    @options.verbosity = 2
    stds = capture_output do
      util_parser "class foo\nend"
      tk = @parser.get_tk
      @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment
    end
    err = stds[1]
    assert_match(/Expected class name or '<<'\. Got/, err)
  end

  def test_parse_syntax_error_code
    @options.verbosity = 2
    stds = capture_output do
      begin
        util_parser <<INVALID_CODE
# invalid class name
class Invalid::@@Code
end
INVALID_CODE
        @parser.scan
      rescue
      end
    end
    err = stds[1]

    expected = <<EXPECTED
RDoc::Parser::Ruby failure around line 2 of
#{@filename}

class Invalid::@@Code
EXPECTED

    assert_match(expected, err)
  end

  def test_parse_multi_ghost_methods
    util_parser <<-'CLASS'
class Foo
  ##
  # :method: one
  #
  # my method

  ##
  # :method: two
  #
  # my method

  [:one, :two].each do |t|
    eval("def #{t}; \"#{t}\"; end")
  end
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    assert_equal 2, foo.method_list.length
  end

  def test_parse_const_fail_w_meta
    util_parser <<-CLASS
class ConstFailMeta
  ##
  # :attr: one
  #
  # an attribute

  OtherModule.define_attr(self, :one)
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    const_fail_meta = @top_level.classes.first
    assert_equal 'ConstFailMeta', const_fail_meta.full_name

    assert_equal 1, const_fail_meta.attributes.length
  end

  def test_parse_class_nested_superclass
    foo = @top_level.add_module RDoc::NormalModule, 'Foo'

    util_parser "class Bar < Super\nend"

    tk = @parser.get_tk

    @parser.parse_class foo, RDoc::Parser::Ruby::NORMAL, tk, @comment

    bar = foo.classes.first
    assert_equal 'Super', bar.superclass
  end

  def test_parse_module
    comment = RDoc::Comment.new "##\n# my module\n", @top_level, :ruby

    util_parser "module Foo\nend"

    tk = @parser.get_tk

    @parser.parse_module @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'my module', foo.comment.text
  end

  def test_parse_module_nodoc
    @top_level.stop_doc

    comment = RDoc::Comment.new "##\n# my module\n", @top_level

    util_parser "module Foo # :nodoc:\nend"

    tk = @parser.get_tk

    @parser.parse_module @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_empty foo.comment
  end

  def test_parse_module_stopdoc
    @top_level.stop_doc

    comment = RDoc::Comment.new "##\n# my module\n", @top_level

    util_parser "module Foo\nend"

    tk = @parser.get_tk

    @parser.parse_module @top_level, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_empty foo.comment
  end

  def test_parse_class_colon3
    code = <<-CODE
class A
  class ::B
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, @comment

    assert_equal %w[A B], @store.all_classes.map { |c| c.full_name }.sort
  end

  def test_parse_class_colon3_self_reference
    code = <<-CODE
class A::B
  class ::A
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, @comment

    assert_equal %w[A A::B], @store.all_classes.map { |c| c.full_name }.sort
  end

  def test_parse_class_single
    code = <<-CODE
class A
  class << B
  end
  class << d = Object.new
    def foo; end
    alias bar foo
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, @comment

    assert_equal %w[A], @store.all_classes.map { |c| c.full_name }

    modules = @store.all_modules.sort_by { |c| c.full_name }
    assert_equal %w[A::B A::d], modules.map { |c| c.full_name }

    b = modules.first
    assert_equal 2,  b.line

    # make sure method/alias was not added to enclosing class/module
    a = @store.classes_hash['A']
    assert_empty a.method_list

    # make sure non-constant-named module will be removed from documentation
    d = @store.modules_hash['A::d']
    assert d.remove_from_documentation?
  end

  def test_parse_class_single_gvar
    code = <<-CODE
class << $g
  def m
  end
end
    CODE

    util_parser code

    @parser.parse_class @top_level, false, @parser.get_tk, ''

    assert_empty @store.all_classes
    mod = @store.all_modules.first

    refute mod.document_self

    assert_empty mod.method_list
  end

  # TODO this is really a Context#add_class test
  def test_parse_class_object
    code = <<-CODE
module A
  class B
  end
  class Object
  end
  class C < Object
  end
end
    CODE

    util_parser code

    @parser.parse_module @top_level, false, @parser.get_tk, @comment

    assert_equal %w[A],
      @store.all_modules.map { |c| c.full_name }
    assert_equal %w[A::B A::C A::Object],
      @store.all_classes.map { |c| c.full_name }.sort

    assert_equal 'Object',    @store.classes_hash['A::B'].superclass
    assert_equal 'Object',    @store.classes_hash['A::Object'].superclass
    assert_equal 'A::Object', @store.classes_hash['A::C'].superclass.full_name
  end

  def test_parse_class_mistaken_for_module
    # The code below is not strictly legal Ruby (Foo must have been defined
    # before Foo::Bar is encountered), but RDoc might encounter Foo::Bar
    # before Foo if they live in different files.

    code = <<-RUBY
class Foo::Bar
end

module Foo::Baz
end

class Foo
end
    RUBY

    util_parser code

    @parser.scan

    assert_equal %w[Foo::Baz], @store.modules_hash.keys
    assert_empty @top_level.modules

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    bar = foo.classes.first
    assert_equal 'Foo::Bar', bar.full_name

    baz = foo.modules.first
    assert_equal 'Foo::Baz', baz.full_name
  end

  def test_parse_class_definition_encountered_after_class_reference
    # The code below is not legal Ruby (Foo must have been defined before
    # Foo.bar is encountered), but RDoc might encounter Foo.bar before Foo if
    # they live in different files.

    code = <<-EOF
def Foo.bar
end

class Foo < IO
end
    EOF

    util_parser code

    @parser.scan

    assert_empty @store.modules_hash
    assert_empty @store.all_modules

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'IO', foo.superclass

    bar = foo.method_list.first
    assert_equal 'bar', bar.name
  end

  def test_parse_module_relative_to_top_level_namespace
    comment = RDoc::Comment.new <<-EOF, @top_level
#
# Weirdly named module
#
EOF

    code = <<-EOF
#{comment.text}
module ::Foo
  class Helper
  end
end
EOF

    util_parser code
    @parser.scan()

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name
    assert_equal 'Weirdly named module', foo.comment.text

    helper = foo.classes.first
    assert_equal 'Foo::Helper', helper.full_name
  end

  def test_parse_comment_attr
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# :attr: foo\n# my attr\n", @top_level, :ruby

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo',      foo.name
    assert_equal 'RW',       foo.rw
    assert_equal 'my attr',  foo.comment.text
    assert_equal @top_level, foo.file
    assert_equal 1,          foo.line

    assert_nil               foo.viewer
    assert_equal true,       foo.document_children
    assert_equal true,       foo.document_self
    assert_equal false,      foo.done_documenting
    assert_equal false,      foo.force_documentation
    assert_equal klass,      foo.parent
    assert_equal :public,    foo.visibility
    assert_equal "\n",       foo.text

    assert_equal klass.current_section, foo.section
  end

  def test_parse_comment_attr_attr_reader
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# :attr_reader: foo\n", @top_level

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.attributes.first
    assert_equal 'foo',      foo.name
    assert_equal 'R',        foo.rw
  end

  def test_parse_comment_attr_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# :attr: foo\n# my attr\n", @top_level

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    assert_empty klass.attributes
  end

  def test_parse_comment_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# :method: foo\n# my method\n", @top_level, :ruby

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',       foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
    assert_equal 2,           foo.line

    assert_equal [],          foo.aliases
    assert_nil                foo.block_params
    assert_nil                foo.call_seq
    assert_nil                foo.is_alias_for
    assert_nil                foo.viewer
    assert_equal true,        foo.document_children
    assert_equal true,        foo.document_self
    assert_equal '',          foo.params
    assert_equal false,       foo.done_documenting
    assert_equal false,       foo.dont_rename_initialize
    assert_equal false,       foo.force_documentation
    assert_equal klass,       foo.parent
    assert_equal false,       foo.singleton
    assert_equal :public,     foo.visibility
    assert_equal "\n",        foo.text
    assert_equal klass.current_section, foo.section

    stream = [
      {
        :line_no => 2, :char_no => 1, :kind => :on_comment,
        :text => "# File #{@top_level.relative_name}, line 2"
      },
      { :line_no => 0, :char_no => 0, :kind => :on_nl, :text => "\n" },
      { :line_no => 1, :char_no => 1, :kind => :on_sp, :text => '' }
    ]
    parsed_stream = foo.token_stream.map { |t|
      {
        :line_no => t[:line_no],
        :char_no => t[:char_no],
        :kind => t[:kind],
        :text => t[:text]
      }
    }

    assert_equal stream, parsed_stream
  end

  def test_parse_comment_method_args
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level


    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk,
                          comment("##\n# :method: foo\n# :args: a, b\n")

    foo = klass.method_list.first
    assert_equal 'foo',  foo.name
    assert_equal 'a, b', foo.params
  end

  def test_parse_comment_method_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# :method: foo\n# my method\n", @top_level

    util_parser "\n"

    tk = @parser.get_tk

    @parser.parse_comment klass, tk, comment

    assert_empty klass.method_list
  end

  def test_parse_constant
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "A = v"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment

    foo = klass.constants.first

    assert_equal 'A', foo.name
    assert_equal @top_level, foo.file
    assert_equal 1, foo.line
  end

  def test_parse_constant_attrasgn
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "A[k] = v"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment

    assert klass.constants.empty?
  end

  def test_parse_constant_alias
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'
    klass.add_class RDoc::NormalClass, 'B'

    util_parser "A = B"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment

    assert_equal [], klass.modules.map(&:full_name)
    assert_equal ['Foo::B', 'Foo::A'], klass.classes.map(&:full_name)
    assert_equal ['Foo::A'], klass.constants.map(&:full_name)
    assert_equal 'Foo::A', klass.find_module_named('A').full_name
  end

  def test_parse_constant_alias_same_name
    foo = @top_level.add_class RDoc::NormalClass, 'Foo'
    @top_level.add_class RDoc::NormalClass, 'Bar'
    bar = foo.add_class RDoc::NormalClass, 'Bar'

    assert @store.find_class_or_module('::Bar')

    util_parser "A = ::Bar"

    tk = @parser.get_tk

    @parser.parse_constant foo, tk, @comment

    assert_equal 'A', bar.find_module_named('A').full_name
  end

  def test_parse_constant_in_method
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser 'A::B = v'

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment, true

    assert_empty klass.constants

    assert_empty @store.modules_hash.keys
    assert_equal %w[Foo], @store.classes_hash.keys
  end

  def test_parse_constant_rescue
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "A => e"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment

    assert_empty klass.constants
    assert_empty klass.modules

    assert_empty @store.modules_hash.keys
    assert_equal %w[Foo], @store.classes_hash.keys
  end

  def test_parse_constant_stopdoc
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'
    klass.stop_doc

    util_parser "A = v"

    tk = @parser.get_tk

    @parser.parse_constant klass, tk, @comment

    assert_empty klass.constants
  end

  def test_parse_comment_nested
    content = <<-CONTENT
A::B::C = 1
    CONTENT

    util_parser content

    tk = @parser.get_tk

    parsed = @parser.parse_constant @top_level, tk, 'comment'

    assert parsed

    a = @top_level.find_module_named 'A'
    b = a.find_module_named 'B'
    c = b.constants.first

    assert_equal 'A::B::C', c.full_name
    assert_equal 'comment', c.comment
  end

  def test_parse_class_the_same_of_outside
    util_parser <<-RUBY
module A
  class A::B
  end
end
    RUBY

    @parser.scan

    assert_includes @store.modules_hash, 'A'
    module_a = @store.find_module_named 'A'
    refute_empty module_a.classes_hash
    assert_includes module_a.classes_hash, 'B'
    refute_includes module_a.classes_hash, 'A'
  end

  def test_parse_constant_the_same_of_outside
    util_parser <<-RUBY
module A
  class B
    class C
    end
  end

  def self.foo
    A::B::C
  end
end
    RUBY

    expected = <<EXPECTED
<span class="ruby-keyword">def</span> <span class="ruby-keyword">self</span>.<span class="ruby-identifier ruby-title">foo</span>
  <span class="ruby-constant">A</span><span class="ruby-operator">::</span><span class="ruby-constant">B</span><span class="ruby-operator">::</span><span class="ruby-constant">C</span>
<span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    module_a = @store.find_module_named 'A'
    foo = module_a.method_list.first
    markup_code = foo.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_constant_with_bracket
    util_parser <<-RUBY
class Klass
end

class Klass2
  CONSTANT = Klass
end

class Klass3
  CONSTANT_2 = {}
  CONSTANT_2[1] = Klass
end
    RUBY

    @parser.scan

    klass = @store.find_class_named 'Klass'
    klass2 = @store.find_class_named 'Klass2'
    klass3 = @store.find_class_named 'Klass3'
    assert_equal klass, klass2.constants.first.is_alias_for
    refute_equal klass, klass3.constants.first.is_alias_for
    assert_nil klass3.find_module_named 'CONSTANT_2'
  end

  def test_parse_extend_or_include_extend
    klass = RDoc::NormalClass.new 'C'
    klass.parent = @top_level

    comment = RDoc::Comment.new "# my extend\n", @top_level, :ruby

    util_parser "extend I"

    @parser.get_tk # extend

    @parser.parse_extend_or_include RDoc::Extend, klass, comment

    assert_equal 1, klass.extends.length

    ext = klass.extends.first
    assert_equal 'I', ext.name
    assert_equal 'my extend', ext.comment.text
    assert_equal @top_level, ext.file
  end

  def test_parse_extend_or_include_include
    klass = RDoc::NormalClass.new 'C'
    klass.parent = @top_level

    comment = RDoc::Comment.new "# my include\n", @top_level, :ruby

    util_parser "include I"

    @parser.get_tk # include

    @parser.parse_extend_or_include RDoc::Include, klass, comment

    assert_equal 1, klass.includes.length

    incl = klass.includes.first
    assert_equal 'I', incl.name
    assert_equal 'my include', incl.comment.text
    assert_equal @top_level, incl.file
  end

  def test_parse_meta_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',       foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
    assert_equal 1,           foo.line

    assert_equal [],      foo.aliases
    assert_nil            foo.block_params
    assert_nil            foo.call_seq
    assert_equal true,    foo.document_children
    assert_equal true,    foo.document_self
    assert_equal false,   foo.done_documenting
    assert_equal false,   foo.dont_rename_initialize
    assert_equal false,   foo.force_documentation
    assert_nil            foo.is_alias_for
    assert_equal '',      foo.params
    assert_equal klass,   foo.parent
    assert_equal false,   foo.singleton
    assert_equal 'add_my_method :foo', foo.text
    assert_nil            foo.viewer
    assert_equal :public, foo.visibility
    assert_equal klass.current_section, foo.section

    stream = [
      {
        :line_no => 1, :char_no => 1, :kind => :on_comment,
        :text => "# File #{@top_level.relative_name}, line 1"
      },
      { :line_no => 0, :char_no => 0, :kind => :on_nl, :text => "\n" },
      { :line_no => 1, :char_no => 1, :kind => :on_sp, :text => '' },
      { :line_no => 1, :char_no => 0, :kind => :on_ident, :text => 'add_my_method' },
      { :line_no => 1, :char_no => 13, :kind => :on_sp, :text => ' ' },
      { :line_no => 1, :char_no => 14, :kind => :on_symbol, :text => ':foo' },
      { :line_no => 1, :char_no => 18, :kind => :on_comma, :text => ',' },
      { :line_no => 1, :char_no => 19, :kind => :on_sp, :text => ' ' },
      { :line_no => 1, :char_no => 20, :kind => :on_symbol, :text => ':bar' },
      { :line_no => 1, :char_no => 24, :kind => :on_nl, :text => "\n" }
    ]
    parsed_stream = foo.token_stream.map { |t|
      {
        :line_no => t[:line_no],
        :char_no => t[:char_no],
        :kind => t[:kind],
        :text => t[:text]
      }
    }

    assert_equal stream, parsed_stream
  end

  def test_parse_meta_method_block
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my method\n", @top_level

    content = <<-CONTENT
inline(:my_method) do |*args|
  "this method causes z to disappear"
end
    CONTENT

    util_parser content

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    rest = { :line_no => 3, :char_no => 3, :kind => :on_nl, :text => "\n" }
    tk = @parser.get_tk
    tk = { :line_no => tk[:line_no], :char_no => tk[:char_no], :kind => tk[:kind], :text => tk[:text] }
    assert_equal rest, tk
  end

  def test_parse_meta_method_define_method
    klass = RDoc::NormalClass.new 'Foo'
    comment = RDoc::Comment.new "##\n# my method\n", @top_level, :ruby

    util_parser "define_method :foo do end"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_meta_method_name
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :method: woo_hoo!\n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'woo_hoo!',  foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_meta_method_singleton
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :singleton-method:\n# my method\n", @top_level, :ruby

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal true, foo.singleton, 'singleton method'
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_meta_method_singleton_name
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment =
      RDoc::Comment.new "##\n# :singleton-method: woo_hoo!\n# my method\n",
                        @top_level, :ruby

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'woo_hoo!', foo.name
    assert_equal true, foo.singleton, 'singleton method'
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_meta_method_string_name
    klass = RDoc::NormalClass.new 'Foo'
    comment = RDoc::Comment.new "##\n# my method\n", @top_level, :ruby

    util_parser "add_my_method 'foo'"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_meta_method_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# my method\n", @top_level

    util_parser "add_my_method :foo, :bar\nadd_my_method :baz"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty klass.method_list
  end

  def test_parse_meta_method_unknown
    klass = RDoc::NormalClass.new 'Foo'
    comment = RDoc::Comment.new "##\n# my method\n", @top_level, :ruby

    util_parser "add_my_method ('foo')"

    tk = @parser.get_tk

    @parser.parse_meta_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'unknown', foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
  end

  def test_parse_method
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "##\n# my method\n", @top_level, :ruby

    util_parser "def foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    foo = klass.method_list.first
    assert_equal 'foo',       foo.name
    assert_equal 'my method', foo.comment.text
    assert_equal @top_level,  foo.file
    assert_equal 1,           foo.line

    assert_equal [],        foo.aliases
    assert_nil              foo.block_params
    assert_nil              foo.call_seq
    assert_nil              foo.is_alias_for
    assert_nil              foo.viewer
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
      {
        :line_no => 1, :char_no => 1, :kind => :on_comment,
        :text => "# File #{@top_level.relative_name}, line 1" },
      { :line_no => 0, :char_no => 0, :kind => :on_nl, :text => "\n" },
      { :line_no => 1, :char_no => 1, :kind => :on_sp, :text => '' },
      { :line_no => 1, :char_no => 0, :kind => :on_kw, :text => 'def' },
      { :line_no => 1, :char_no => 3, :kind => :on_sp, :text => ' ' },
      { :line_no => 1, :char_no => 4, :kind => :on_ident, :text => 'foo' },
      { :line_no => 1, :char_no => 7, :kind => :on_lparen, :text => '(' },
      { :line_no => 1, :char_no => 8, :kind => :on_rparen, :text => ')' },
      { :line_no => 1, :char_no => 9, :kind => :on_sp, :text => ' ' },
      { :line_no => 1, :char_no => 10, :kind => :on_symbol, :text => ':bar' },
      { :line_no => 1, :char_no => 14, :kind => :on_sp, :text => ' ' },
      { :line_no => 1, :char_no => 15, :kind => :on_kw, :text => 'end' }
    ]
    parsed_stream = foo.token_stream.map { |t|
      {
        :line_no => t[:line_no],
        :char_no => t[:char_no],
        :kind => t[:kind],
        :text => t[:text]
      }
    }
    assert_equal stream, parsed_stream
  end

  def test_parse_redefinable_methods
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    comment = RDoc::Comment.new "", @top_level

    redefinable_ops = %w[| ^ & <=> == === =~ > >= < <= << >> + - * / % ** ~ +@ -@ [] []= ` !  != !~]
    redefinable_ops.each do |redefinable_op|
      util_parser "def #{redefinable_op}\nend\n"
      tk = @parser.get_tk
      @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment
    end

    klass.method_list.each do |method|
      assert_equal :on_ident, method.token_stream[5][:kind]
      assert_includes redefinable_ops, method.token_stream[5][:text]
    end
  end

  def test_parse_method_with_args_directive
    util_parser <<-RUBY
class C
  def meth_with_args_after # :args: a, b, c
  end

  ##
  # :args: d, e, f
  def meth_with_args_before
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'

    assert_equal 'C#meth_with_args_after', c.method_list[0].full_name
    assert_equal 'a, b, c', c.method_list[0].params
    assert_equal 'C#meth_with_args_before', c.method_list[1].full_name
    assert_equal 'd, e, f', c.method_list[1].params
  end

  def test_parse_method_bracket
    util_parser <<-RUBY
class C
  def [] end
  def self.[] end
  def []= end
  def self.[]= end
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'

    assert_equal 4, c.method_list.size
    assert_equal 'C#[]', c.method_list[0].full_name
    assert_equal 'C::[]', c.method_list[1].full_name
    assert_equal 'C#[]=', c.method_list[2].full_name
    assert_equal 'C::[]=', c.method_list[3].full_name
    assert c.aliases.empty?
  end

  def test_parse_method_alias
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def m() alias a b; end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert klass.aliases.empty?
  end

  def test_parse_method_ampersand
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def self.&\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    ampersand = klass.method_list.first
    assert_equal '&', ampersand.name
    assert            ampersand.singleton
  end

  def test_parse_method_constant
    c = RDoc::Constant.new 'CONST', nil, ''
    m = @top_level.add_class RDoc::NormalModule, 'M'
    m.add_constant c

    util_parser "def CONST.m() end"

    tk = @parser.get_tk

    @parser.parse_method m, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert_empty @store.modules_hash.keys
    assert_equal %w[M], @store.classes_hash.keys
  end

  def test_parse_method_false
    util_parser "def false.foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    klass = @store.find_class_named 'FalseClass'

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
  end

  def test_parse_method_funky
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def (blah).foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert_empty klass.method_list
  end

  def test_parse_method_gvar
    util_parser "def $stdout.foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert @top_level.method_list.empty?
  end

  def test_parse_method_gvar_insane
    util_parser "def $stdout.foo() class << $other; end; end"

    tk = @parser.get_tk

    @parser.parse_method @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert @top_level.method_list.empty?

    assert_empty @store.all_classes

    assert_equal 1, @store.all_modules.length

    refute @store.all_modules.first.document_self
  end

  def test_parse_method_internal_gvar
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo() def $blah.bar() end end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert_equal 1, klass.method_list.length
  end

  def test_parse_method_internal_ivar
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo() def @blah.bar() end end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert_equal 1, klass.method_list.length
  end

  def test_parse_method_internal_lvar
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo() def blah.bar() end end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    assert_equal 1, klass.method_list.length
  end

  def test_parse_method_nil
    util_parser "def nil.foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    klass = @store.find_class_named 'NilClass'

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
  end

  def test_parse_method_nodoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo # :nodoc:\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment('')

    assert_empty klass.method_list
  end

  def test_parse_method_nodoc_track
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    @options.visibility = :nodoc

    util_parser "def foo # :nodoc:\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment('')

    refute_empty klass.method_list
  end

  def test_parse_method_no_parens
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo arg1, arg2 = {}\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2 = {})', foo.params
    assert_equal @top_level, foo.file
  end

  def test_parse_method_parameters_comment
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo arg1, arg2 # some useful comment\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2)', foo.params
  end

  def test_parse_method_parameters_comment_continue
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo arg1, arg2, # some useful comment\narg3\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2, arg3)', foo.params
  end

  def test_parse_method_parameters_with_paren_comment_continue
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo(arg1, arg2, # some useful comment\narg3)\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = klass.method_list.first
    assert_equal '(arg1, arg2, arg3)', foo.params
  end

  def test_parse_method_star
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def self.*\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    ampersand = klass.method_list.first
    assert_equal '*', ampersand.name
    assert            ampersand.singleton
  end

  def test_parse_method_stopdoc
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level
    klass.stop_doc

    comment = RDoc::Comment.new "##\n# my method\n", @top_level

    util_parser "def foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, comment

    assert_empty klass.method_list
  end

  def test_parse_method_toplevel
    klass = @top_level

    util_parser "def foo arg1, arg2\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    object = @store.find_class_named 'Object'

    foo = object.method_list.first
    assert_equal 'Object#foo', foo.full_name
    assert_equal @top_level, foo.file
  end

  def test_parse_method_toplevel_class
    klass = @top_level

    util_parser "def Object.foo arg1, arg2\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    object = @store.find_class_named 'Object'

    foo = object.method_list.first
    assert_equal 'Object::foo', foo.full_name
  end

  def test_parse_method_true
    util_parser "def true.foo() :bar end"

    tk = @parser.get_tk

    @parser.parse_method @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    klass = @store.find_class_named 'TrueClass'

    foo = klass.method_list.first
    assert_equal 'foo', foo.name
  end

  def test_parse_method_utf8
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    method = "def ω() end"

    assert_equal Encoding::UTF_8, method.encoding

    util_parser method

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    omega = klass.method_list.first
    assert_equal "def \317\211", omega.text
  end

  def test_parse_method_dummy
    util_parser ".method() end"

    @parser.parse_method_dummy @top_level

    assert_nil @parser.get_tk
  end

  def test_parse_method_or_yield_parameters_hash
    util_parser "({})\n"

    m = RDoc::AnyMethod.new nil, 'm'

    result = @parser.parse_method_or_yield_parameters m

    assert_equal '({})', result
  end

  def test_parse_statements_class_if
    util_parser <<-CODE
module Foo
  X = if TRUE then
        ''
      end

  def blah
  end
end
    CODE

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name, 'module Foo'

    methods = foo.method_list
    assert_equal 1, methods.length
    assert_equal 'Foo#blah', methods.first.full_name
  end

  def test_parse_statements_postfix_if_unless
    util_parser <<-CODE
class C
  def foo
    1 if nil
  end

  def bar
    2 unless nil
  end
end
    CODE

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil

    c = @top_level.classes.first
    assert_equal 'C', c.full_name, 'class C'

    methods = c.method_list
    assert_equal 2, methods.length
    assert_equal 'C#foo', methods[0].full_name
    assert_equal 'C#bar', methods[1].full_name
  end

  def test_parse_statements_postfix_if_unless_with_expr_mid
    util_parser <<-CODE
class A
  class B
    def foo
      return if nil
    end
  end

  class C
  end
end
    CODE

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil

    a = @top_level.classes.first
    assert_equal 'A', a.full_name, 'class A'
    assert_equal 2, a.classes.length
    b = a.classes[0]
    assert_equal 'A::B', b.full_name, 'class A::B'
    c = a.classes[1]
    assert_equal 'A::C', c.full_name, 'class A::C'
  end

  def test_parse_statements_class_nested
    comment = RDoc::Comment.new "##\n# my method\n", @top_level

    util_parser "module Foo\n#{comment.text}class Bar\nend\nend"

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL

    foo = @top_level.modules.first
    assert_equal 'Foo', foo.full_name, 'module Foo'

    bar = foo.classes.first
    assert_equal 'Foo::Bar', bar.full_name, 'class Foo::Bar'
    assert_equal 'my method', bar.comment.text
  end

  def test_parse_statements_def_percent_string_pound
    util_parser "class C\ndef a\n%r{#}\n%r{\#{}}\nend\ndef b() end\nend"

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL

    x = @top_level.classes.first

    assert_equal 2, x.method_list.length
    a = x.method_list.first


    expected = [
      {
        :line_no => 2, :char_no => 1, :kind => :on_comment,
        :text => "# File #{@filename}, line 2"
      },
      { :line_no => 0, :char_no => 0, :kind => :on_nl, :text => "\n" },
      { :line_no => 1, :char_no => 1, :kind => :on_sp, :text => '' },
      { :line_no => 2, :char_no => 0, :kind => :on_kw, :text => 'def' },
      { :line_no => 2, :char_no => 3, :kind => :on_sp, :text => ' ' },
      { :line_no => 2, :char_no => 4, :kind => :on_ident, :text => 'a' },
      { :line_no => 2, :char_no => 5, :kind => :on_nl, :text => "\n" },
      { :line_no => 3, :char_no => 0, :kind => :on_regexp, :text => '%r{#}' },
      { :line_no => 3, :char_no => 5, :kind => :on_nl, :text => "\n" },
      { :line_no => 4, :char_no => 0, :kind => :on_regexp, :text => '%r{#{}}' },
      { :line_no => 4, :char_no => 7, :kind => :on_nl, :text => "\n" },
      { :line_no => 5, :char_no => 0, :kind => :on_kw, :text => 'end' }
    ]
    parsed_stream = a.token_stream.map { |tk|
      {
        :line_no => tk[:line_no],
        :char_no => tk[:char_no],
        :kind => tk[:kind],
        :text => tk[:text]
      }
    }

    assert_equal expected, parsed_stream
  end

  def test_parse_statements_encoding
    @options.encoding = Encoding::CP852

    content = <<-EOF
class Foo
  ##
  # this is my method
  add_my_method :foo
end
    EOF

    util_parser content

    @parser.parse_statements @top_level

    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
    assert_equal 'this is my method', foo.comment.text
    assert_equal Encoding::CP852, foo.comment.text.encoding
  end

  def test_parse_statements_enddoc
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :enddoc:"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert klass.done_documenting
  end

  def test_parse_statements_enddoc_top_level
    util_parser "\n# :enddoc:"

    assert_throws :eof do
      @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, nil
    end
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

    @parser.parse_statements @top_level

    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
  end

  def test_parse_statements_identifier_alias_method
    content = <<-RUBY
class Foo
  def foo() end
  alias_method :foo2, :foo
end
    RUBY

    util_parser content

    @parser.parse_statements @top_level

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

    @parser.parse_statements @top_level

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

    assert_equal 'unknown', @top_level.classes.first.external_aliases[0].old_name
  end

  def test_parse_statements_identifier_args
    comment = "##\n# :args: x\n# :method: b\n# my method\n"

    util_parser "module M\n#{comment}def_delegator :a, :b, :b\nend"

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL

    m = @top_level.modules.first
    assert_equal 'M', m.full_name

    b = m.method_list.first
    assert_equal 'M#b', b.full_name
    assert_equal 'x', b.params
    assert_equal 'my method', b.comment.text

    assert_nil m.params, 'Module parameter not removed'
  end

  def test_parse_statements_identifier_constant
    sixth_constant = <<-EOF
Class.new do
  rule :file do
    all(x, y, z) {
      def value
        find(:require).each {|r| require r.value }
        find(:grammar).map {|g| g.value }
      end
      def min; end
    }
  end
end
    EOF

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

  SIXTH_CONSTANT = #{sixth_constant}

  SEVENTH_CONSTANT = proc { |i| begin i end }

  EIGHTH_CONSTANT = "a" \\
                    "b"
end
EOF

    util_parser content

    @parser.parse_statements @top_level

    constants = @top_level.classes.first.constants

    constant = constants[0]
    assert_equal 'FIRST_CONSTANT', constant.name
    assert_equal '5', constant.value
    assert_equal @top_level, constant.file

    constant = constants[1]
    assert_equal 'SECOND_CONSTANT', constant.name
    assert_equal "[\n1,\n2,\n3\n]", constant.value
    assert_equal @top_level, constant.file

    constant = constants[2]
    assert_equal 'THIRD_CONSTANT', constant.name
    assert_equal "{\n:foo => 'bar',\n:x => 'y'\n}", constant.value
    assert_equal @top_level, constant.file

    constant = constants[3]
    assert_equal 'FOURTH_CONSTANT', constant.name
    assert_equal "SECOND_CONSTANT.map do |element|\nelement + 1\nelement + 2\nend", constant.value
    assert_equal @top_level, constant.file

    constant = constants[4]
    assert_equal 'FIFTH_CONSTANT', constant.name
    assert_equal 'SECOND_CONSTANT.map { |element| element + 1 }', constant.value
    assert_equal @top_level, constant.file

    # TODO: parse as class
    constant = constants[5]
    assert_equal 'SIXTH_CONSTANT', constant.name
    assert_equal sixth_constant.lines.map(&:strip).join("\n"), constant.value
    assert_equal @top_level, constant.file

    # TODO: parse as method
    constant = constants[6]
    assert_equal 'SEVENTH_CONSTANT', constant.name
    assert_equal "proc { |i| begin i end }", constant.value
    assert_equal @top_level, constant.file

    constant = constants[7]
    assert_equal 'EIGHTH_CONSTANT', constant.name
    assert_equal "\"a\" \\\n\"b\"", constant.value
    assert_equal @top_level, constant.file
  end

  def test_parse_statements_identifier_attr
    content = "class Foo\nattr :foo\nend"

    util_parser content

    @parser.parse_statements @top_level

    foo = @top_level.classes.first.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'R', foo.rw
  end

  def test_parse_statements_identifier_attr_accessor
    content = "class Foo\nattr_accessor :foo\nend"

    util_parser content

    @parser.parse_statements @top_level

    foo = @top_level.classes.first.attributes.first
    assert_equal 'foo', foo.name
    assert_equal 'RW', foo.rw
  end

  def test_parse_statements_identifier_define_method
    util_parser <<-RUBY
class C
  ##
  # :method: a
  define_method :a do end
  ##
  # :method: b
  define_method :b do end
end
    RUBY

    @parser.parse_statements @top_level
    c = @top_level.classes.first

    assert_equal %w[a b], c.method_list.map { |m| m.name }
  end

  def test_parse_statements_identifier_include
    content = "class Foo\ninclude Bar\nend"

    util_parser content

    @parser.parse_statements @top_level

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.name
    assert_equal 1, foo.includes.length
  end

  def test_parse_statements_identifier_module_function
    content = "module Foo\ndef foo() end\nmodule_function :foo\nend"

    util_parser content

    @parser.parse_statements @top_level

    foo, s_foo = @top_level.modules.first.method_list
    assert_equal 'foo',    foo.name,       'instance method name'
    assert_equal :private, foo.visibility, 'instance method visibility'
    assert_equal false,    foo.singleton,  'instance method singleton'

    assert_equal 'foo',   s_foo.name,       'module function name'
    assert_equal :public, s_foo.visibility, 'module function visibility'
    assert_equal true,    s_foo.singleton,  'module function singleton'
  end

  def test_parse_statements_identifier_private
    content = "class Foo\nprivate\ndef foo() end\nend"

    util_parser content

    @parser.parse_statements @top_level

    foo = @top_level.classes.first.method_list.first
    assert_equal 'foo', foo.name
    assert_equal :private, foo.visibility
  end

  def test_parse_statements_identifier_public_class_method
    content = <<-CONTENT
class Date
  def self.now; end
  private_class_method :now
end

class DateTime < Date
  public_class_method :now
end
    CONTENT

    util_parser content

    @parser.parse_statements @top_level

    date, date_time = @top_level.classes.sort_by { |c| c.full_name }

    date_now      = date.method_list.first
    date_time_now = date_time.method_list.sort_by { |m| m.full_name }.first

    assert_equal :private, date_now.visibility
    assert_equal :public,  date_time_now.visibility
  end

  def test_parse_statements_identifier_private_class_method
    content = <<-CONTENT
class Date
  def self.now; end
  public_class_method :now
end

class DateTime < Date
  private_class_method :now
end
    CONTENT

    util_parser content

    @parser.parse_statements @top_level

    # TODO sort classes by default
    date, date_time = @top_level.classes.sort_by { |c| c.full_name }

    date_now      = date.method_list.first
    date_time_now = date_time.method_list.sort_by { |m| m.full_name }.first

    assert_equal :public,  date_now.visibility,      date_now.full_name
    assert_equal :private, date_time_now.visibility, date_time_now.full_name
  end

  def test_parse_statements_complex_condition_in_for
    util_parser <<RUBY
class Foo
  def blah()
    for i in (k)...n do
    end
    for i in (k)...n
    end
  end
end
RUBY

    expected = <<EXPECTED
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">blah</span>()
  <span class="ruby-keyword">for</span> <span class="ruby-identifier">i</span> <span class="ruby-keyword">in</span> (<span class="ruby-identifier">k</span>)<span class="ruby-operator">...</span><span class="ruby-identifier">n</span> <span class="ruby-keyword">do</span>
  <span class="ruby-keyword">end</span>
  <span class="ruby-keyword">for</span> <span class="ruby-identifier">i</span> <span class="ruby-keyword">in</span> (<span class="ruby-identifier">k</span>)<span class="ruby-operator">...</span><span class="ruby-identifier">n</span>
  <span class="ruby-keyword">end</span>
<span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_code = blah.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_instance_operation_method
    util_parser <<-RUBY
class Foo
  def self.& end
end
    RUBY

    expected = <<EXPECTED
  <span class="ruby-keyword">def</span> <span class="ruby-keyword">self</span>.<span class="ruby-identifier ruby-title">&amp;</span> <span class="ruby-keyword">end</span>
<span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_code = blah.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_statements_postfix_if_after_heredocbeg
    @filename = 'file.rb'
    util_parser <<RUBY
class Foo
  def blah()
    <<-EOM if true
    EOM
  end
end
RUBY

    expected = <<EXPECTED
  <span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">blah</span>()
    <span class="ruby-identifier">&lt;&lt;-EOM</span> <span class="ruby-keyword">if</span> <span class="ruby-keyword">true</span>
<span class="ruby-value"></span><span class="ruby-identifier">    EOM</span>
  <span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_code = blah.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_mutable_heredocbeg
    @filename = 'file.rb'
    util_parser <<RUBY
class Foo
  def blah()
    @str = -<<-EOM
    EOM
  end
end
RUBY

    expected = <<EXPECTED
  <span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">blah</span>()
    <span class="ruby-ivar">@str</span> = <span class="ruby-identifier">-&lt;&lt;-EOM</span>
<span class="ruby-value"></span><span class="ruby-identifier">    EOM</span>
  <span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_code = blah.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_heredoc_end
    code = "A = <<eos\n""OK\n""eos\n"
    util_parser code
    @parser.parse_statements @top_level
    @parser.scan
    c = @top_level.classes.first.constants.first
    assert_equal("A", c.name)

    util_parser code.gsub(/$/, "\r")
    @parser.parse_statements @top_level
    @parser.scan
    c = @top_level.classes.first.constants.first
    assert_equal("A", c.name)
  end

  def test_parse_statements_method_oneliner_with_regexp
    util_parser <<RUBY
class Foo
  def blah() /bar/ end
end
RUBY

    expected = <<EXPECTED
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">blah</span>() <span class="ruby-regexp">/bar/</span> <span class="ruby-keyword">end</span>
EXPECTED
    expected = expected.rstrip

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_code = blah.markup_code.sub(/^.*\n/, '')
    assert_equal expected, markup_code
  end

  def test_parse_statements_embdoc_in_document
    @filename = 'file.rb'
    util_parser <<RUBY
class Foo
  # doc
  #
  #   =begin
  #   test embdoc
  #   =end
  #
  def blah
  end
end
RUBY

    expected = <<EXPECTED
<p>doc

<pre class="ruby"><span class="ruby-comment">=begin
test embdoc
=end</span>
</pre>
EXPECTED

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    markup_comment = blah.search_record[6]
    assert_equal expected, markup_comment
  end

  def test_parse_require_dynamic_string
    content = <<-RUBY
prefix = 'path'
require "\#{prefix}/a_library"
require 'test'
RUBY

    util_parser content

    @parser.parse_statements @top_level

    assert_equal 1, @top_level.requires.length
  end

  def test_parse_postfix_nodoc
    util_parser <<-RUBY
class A
end # :nodoc:

class B
  def a
  end # :nodoc:

  def b
  end
end
RUBY

    @parser.parse_statements @top_level

    c_a = @top_level.classes.select(&:document_self).first
    assert_equal 'B', c_a.full_name

    assert_equal 2, @top_level.classes.length
    assert_equal 1, @top_level.classes.count(&:document_self)
    assert_equal 1, c_a.method_list.length
    assert_equal 'B#b', c_a.method_list.first.full_name
  end

  def test_parse_statements_identifier_require
    content = "require 'bar'"

    util_parser content

    @parser.parse_statements @top_level

    assert_equal 1, @top_level.requires.length
  end

  def test_parse_statements_identifier_yields
    comment = "##\n# :yields: x\n# :method: b\n# my method\n"

    util_parser "module M\n#{comment}def_delegator :a, :b, :b\nend"

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL

    m = @top_level.modules.first
    assert_equal 'M', m.full_name

    b = m.method_list.first
    assert_equal 'M#b', b.full_name
    assert_equal 'x', b.block_params
    assert_equal 'my method', b.comment.text

    assert_nil m.params, 'Module parameter not removed'
  end

  def test_parse_statements_stopdoc_alias
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :stopdoc:\nalias old new"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert_empty klass.aliases
    assert_empty klass.unmatched_alias_lists
  end

  def test_parse_statements_stopdoc_identifier_alias_method
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :stopdoc:\nalias_method :old :new"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert_empty klass.aliases
    assert_empty klass.unmatched_alias_lists
  end

  def test_parse_statements_stopdoc_identifier_metaprogrammed
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :stopdoc:\n# attr :meta"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert_empty klass.method_list
    assert_empty klass.attributes
  end

  def test_parse_statements_stopdoc_constant
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :stopdoc:\nA = v"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert_empty klass.constants
  end

  def test_parse_statements_stopdoc_def
    klass = @top_level.add_class RDoc::NormalClass, 'Foo'

    util_parser "\n# :stopdoc:\ndef m\n end"

    @parser.parse_statements klass, RDoc::Parser::Ruby::NORMAL, nil

    assert_empty klass.method_list
  end

  def test_parse_statements_super
    m = RDoc::AnyMethod.new '', 'm'
    util_parser 'super'

    @parser.parse_statements @top_level, RDoc::Parser::Ruby::NORMAL, m

    assert m.calls_super
  end

  def test_parse_statements_super_no_method
    content = "super"

    util_parser content

    @parser.parse_statements @top_level

    assert_nil @parser.get_tk
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

    @parser.parse_statements @top_level

    c_a = @top_level.classes.first
    assert_equal 'A', c_a.full_name

    assert_equal 1, @top_level.classes.length

    m_a = c_a.method_list.first
    m_b = c_a.method_list.last

    assert_equal 'A#a', m_a.full_name
    assert_equal 'A#b', m_b.full_name
  end


  def test_parse_symbol_in_paren_arg
    util_parser <<RUBY
class Foo
  def blah
  end
  private(:blah)
end
RUBY

    @parser.scan

    foo = @top_level.classes.first
    assert_equal 'Foo', foo.full_name

    blah = foo.method_list.first
    assert_equal :private, blah.visibility
  end

  def test_parse_symbol_in_arg
    util_parser '[:blah, "blah", "#{blah}", blah]'
    @parser.get_tk # skip '['

    assert_equal 'blah', @parser.parse_symbol_in_arg
    @parser.get_tk # skip ','

    @parser.skip_tkspace

    assert_equal 'blah', @parser.parse_symbol_in_arg
    @parser.get_tk # skip ','

    @parser.skip_tkspace

    assert_nil @parser.parse_symbol_in_arg
    @parser.get_tk # skip ','

    @parser.skip_tkspace

    assert_nil @parser.parse_symbol_in_arg
  end

  def test_parse_statements_alias_method
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

    # HACK where are the assertions?
  end

  def test_parse_top_level_statements_enddoc
    util_parser <<-CONTENT
# :enddoc:
    CONTENT

    assert_throws :eof do
      @parser.parse_top_level_statements @top_level
    end
  end

  def test_parse_top_level_statements_stopdoc
    @top_level.stop_doc
    content = "# this is the top-level comment"

    util_parser content

    @parser.parse_top_level_statements @top_level

    assert_empty @top_level.comment
  end

  def test_parse_top_level_statements_stopdoc_integration
    content = <<-CONTENT
# :stopdoc:

class Example
  def method_name
  end
end
    CONTENT

    util_parser content

    @parser.parse_top_level_statements @top_level

    assert_equal 1, @top_level.classes.length
    assert_empty @top_level.modules

    assert @top_level.find_module_named('Example').ignored?
  end

  # This tests parse_comment
  def test_parse_top_level_statements_constant_nodoc_integration
    content = <<-CONTENT
class A
  C = A # :nodoc:
end
    CONTENT

    util_parser content

    @parser.parse_top_level_statements @top_level

    klass = @top_level.find_module_named('A')

    c = klass.constants.first

    assert_nil c.document_self, 'C should not be documented'
  end

  def test_parse_yield_in_braces_with_parens
    klass = RDoc::NormalClass.new 'Foo'
    klass.parent = @top_level

    util_parser "def foo\nn.times { |i| yield nth(i) }\nend"

    tk = @parser.get_tk

    @parser.parse_method klass, RDoc::Parser::Ruby::NORMAL, tk, @comment

    foo = klass.method_list.first
    assert_equal 'nth(i)', foo.block_params
  end

  def test_read_directive
    parser = util_parser '# :category: test'

    directive, value = parser.read_directive %w[category]

    assert_equal 'category', directive
    assert_equal 'test', value

    assert_nil parser.get_tk
  end

  def test_read_directive_allow
    parser = util_parser '# :category: test'

    directive = parser.read_directive []

    assert_nil directive

    assert_nil parser.get_tk
  end

  def test_read_directive_empty
    parser = util_parser '# test'

    directive = parser.read_directive %w[category]

    assert_nil directive

    assert_nil parser.get_tk
  end

  def test_read_directive_no_comment
    parser = util_parser ''

    directive = parser.read_directive %w[category]

    assert_nil directive

    assert_nil parser.get_tk
  end

  def test_read_directive_one_liner
    parser = util_parser 'AAA = 1 # :category: test'

    directive, value = parser.read_directive %w[category]

    assert_equal 'category', directive
    assert_equal 'test', value

    assert_equal :on_const, parser.get_tk[:kind]
  end

  def test_read_documentation_modifiers
    c = RDoc::Context.new

    parser = util_parser '# :category: test'

    parser.read_documentation_modifiers c, %w[category]

    assert_equal 'test', c.current_section.title
  end

  def test_read_documentation_modifiers_notnew
    m = RDoc::AnyMethod.new nil, 'initialize'

    parser = util_parser '# :notnew: test'

    parser.read_documentation_modifiers m, %w[notnew]

    assert m.dont_rename_initialize
  end

  def test_read_documentation_modifiers_not_dash_new
    m = RDoc::AnyMethod.new nil, 'initialize'

    parser = util_parser '# :not-new: test'

    parser.read_documentation_modifiers m, %w[not-new]

    assert m.dont_rename_initialize
  end

  def test_read_documentation_modifiers_not_new
    m = RDoc::AnyMethod.new nil, 'initialize'

    parser = util_parser '# :not_new: test'

    parser.read_documentation_modifiers m, %w[not_new]

    assert m.dont_rename_initialize
  end

  def test_sanity_integer
    util_parser '1'
    assert_equal '1', @parser.get_tk[:text]

    util_parser '1.0'
    assert_equal '1.0', @parser.get_tk[:text]
  end

  def test_sanity_interpolation
    last_tk = nil
    util_parser 'class A; B = "#{c}"; end'

    while tk = @parser.get_tk do last_tk = tk end

    assert_equal 'end', last_tk[:text]
  end

  # If you're writing code like this you're doing it wrong

  def test_sanity_interpolation_crazy
    util_parser '"#{"#{"a")}" if b}"'

    assert_equal '"#{"#{"a")}" if b}"', @parser.get_tk[:text]
    assert_nil @parser.get_tk
  end

  def test_sanity_interpolation_curly
    util_parser '%{ #{} }'

    assert_equal '%{ #{} }', @parser.get_tk[:text]
    assert_nil @parser.get_tk
  end

  def test_sanity_interpolation_format
    util_parser '"#{stftime("%m-%d")}"'

    while @parser.get_tk do end
  end

  def test_sanity_symbol_interpolation
    util_parser ':"#{bar}="'

    while @parser.get_tk do end
  end

  def test_scan_cr
    content = <<-CONTENT
class C\r
  def m\r
    a=\\\r
      123\r
  end\r
end\r
    CONTENT

    util_parser content

    @parser.scan

    c = @top_level.classes.first

    assert_equal 1, c.method_list.length
  end

  def test_scan_block_comment
    content = <<-CONTENT
=begin rdoc
Foo comment
=end

class Foo

=begin
m comment
=end

  def m() end
end
    CONTENT

    util_parser content

    @parser.scan

    foo = @top_level.classes.first

    assert_equal 'Foo comment', foo.comment.text

    m = foo.method_list.first

    assert_equal 'm comment', m.comment.text
  end

  def test_scan_block_comment_nested # Issue #41
    content = <<-CONTENT
require 'something'
=begin rdoc
findmeindoc
=end
module Foo
    class Bar
    end
end
    CONTENT

    util_parser content

    @parser.scan

    foo = @top_level.modules.first

    assert_equal 'Foo', foo.full_name
    assert_equal 'findmeindoc', foo.comment.text

    bar = foo.classes.first

    assert_equal 'Foo::Bar', bar.full_name
    assert_equal '', bar.comment.text
  end

  def test_scan_block_comment_notflush
  ##
  #
  # The previous test assumes that between the =begin/=end blocks that there
  # is only one line, or minima formatting directives. This test tests for
  # those who use the =begin block with longer / more advanced formatting
  # within.
  #
  ##
    content = <<-CONTENT
=begin rdoc

= DESCRIPTION

This is a simple test class

= RUMPUS

Is a silly word

=end
class StevenSimpleClass
  # A band on my iPhone as I wrote this test
  FRUIT_BATS="Make nice music"

=begin rdoc
A nice girl
=end

  def lauren
    puts "Summoning Lauren!"
  end
end
    CONTENT
    util_parser content

    @parser.scan

    foo = @top_level.classes.first

    assert_equal "= DESCRIPTION\n\nThis is a simple test class\n\n= RUMPUS\n\nIs a silly word",
      foo.comment.text

    m = foo.method_list.first

    assert_equal 'A nice girl', m.comment.text
  end

  def test_scan_class_nested_nodoc
    content = <<-CONTENT
class A::B # :nodoc:
end
    CONTENT

    util_parser content

    @parser.scan

    visible = @store.all_classes_and_modules.select { |mod| mod.display? }

    assert_empty visible.map { |mod| mod.full_name }
  end

  def test_scan_constant_in_method
    content = <<-CONTENT # newline is after M is important
module M
  def m
    A
    B::C
  end
end
    CONTENT

    util_parser content

    @parser.scan

    m = @top_level.modules.first

    assert_empty m.constants

    assert_empty @store.classes_hash.keys
    assert_equal %w[M], @store.modules_hash.keys
  end

  def test_scan_constant_in_rescue
    content = <<-CONTENT # newline is after M is important
module M
  def m
  rescue A::B
  rescue A::C => e
  rescue A::D, A::E
  rescue A::F,
         A::G
  rescue H
  rescue I => e
  rescue J, K
  rescue L =>
    e
  rescue M;
  rescue N,
         O => e
  end
end
    CONTENT

    util_parser content

    @parser.scan

    m = @top_level.modules.first

    assert_empty m.constants

    assert_empty @store.classes_hash.keys
    assert_equal %w[M], @store.modules_hash.keys
  end

  def test_scan_constant_nodoc
    content = <<-CONTENT # newline is after M is important
module M

  C = v # :nodoc:
end
    CONTENT

    util_parser content

    @parser.scan

    c = @top_level.modules.first.constants.first

    assert c.documented?
  end

  def test_scan_constant_nodoc_block
    content = <<-CONTENT # newline is after M is important
module M

  C = v do # :nodoc:
  end
end
    CONTENT

    util_parser content

    @parser.scan

    c = @top_level.modules.first.constants.first

    assert c.documented?
  end

  def test_scan_duplicate_module
    content = <<-CONTENT
# comment a
module Foo
end

# comment b
module Foo
end
    CONTENT

    util_parser content

    @parser.scan

    foo = @top_level.modules.first

    expected = [
      RDoc::Comment.new('comment a', @top_level),
      RDoc::Comment.new('comment b', @top_level)
    ]

    assert_equal expected, foo.comment_location.map { |c, l| c }
  end

  def test_scan_meta_method_block
    content = <<-CONTENT
class C

  ##
  #  my method

  inline(:my_method) do |*args|
    "this method used to cause z to disappear"
  end

  def z
  end
    CONTENT

    util_parser content

    @parser.scan

    assert_equal 2, @top_level.classes.first.method_list.length
  end

  def test_scan_method_semi_method
    content = <<-CONTENT
class A
  def self.m() end; def self.m=() end
end

class B
  def self.m() end
end
    CONTENT

    util_parser content

    @parser.scan

    a = @store.find_class_named 'A'
    assert a, 'missing A'

    assert_equal 2, a.method_list.length

    b = @store.find_class_named 'B'
    assert b, 'missing B'

    assert_equal 1, b.method_list.length
  end

  def test_scan_markup_override
    content = <<-CONTENT
# *awesome*
class C
  # :markup: rd
  # ((*radical*))
  def m
  end
end
    CONTENT

    util_parser content

    @parser.scan

    c = @top_level.classes.first

    assert_equal 'rdoc', c.comment.format

    assert_equal 'rd', c.method_list.first.comment.format
  end

  def test_scan_markup_first_comment
    content = <<-CONTENT
# :markup: rd

# ((*awesome*))
class C
  # ((*radical*))
  def m
  end
end
    CONTENT

    util_parser content

    @parser.scan

    c = @top_level.classes.first

    assert_equal 'rd', c.comment.format

    assert_equal 'rd', c.method_list.first.comment.format
  end

  def test_scan_rails_routes
    util_parser <<-ROUTES_RB
namespace :api do
  scope module: :v1 do
  end
end
    ROUTES_RB

    @parser.scan

    assert_empty @top_level.classes
    assert_empty @top_level.modules
  end

  def test_scan_tomdoc_meta
    util_parser <<-RUBY
# :markup: tomdoc

class C

  # Signature
  #
  #   find_by_<field>[_and_<field>...](args)
  #
  # field - A field name.

end

    RUBY

    @parser.scan

    c = @top_level.classes.first

    m = c.method_list.first

    assert_equal "find_by_<field>[_and_<field>...]", m.name
    assert_equal "find_by_<field>[_and_<field>...](args)\n", m.call_seq

    expected =
      doc(
        head(3, 'Signature'),
        list(:NOTE,
          item(%w[field],
            para('A field name.'))))
    expected.file = @top_level

    assert_equal expected, m.comment.parse
  end

  def test_scan_stopdoc
    util_parser <<-RUBY
class C
  # :stopdoc:
  class Hidden
  end
end
    RUBY

    @parser.scan

    c = @top_level.classes.first

    hidden = c.classes.first

    refute hidden.document_self
    assert hidden.ignored?
  end

  def test_scan_stopdoc_class_alias
    util_parser <<-RUBY
# :stopdoc:
module A
  B = C
end
    RUBY

    @parser.scan

    assert_empty @store.all_classes

    assert_equal 1, @store.all_modules.length
    m = @store.all_modules.first

    assert m.ignored?
  end

  def test_scan_stopdoc_nested
    util_parser <<-RUBY
# :stopdoc:
class A::B
end
    RUBY

    @parser.scan

    a   = @store.modules_hash['A']
    a_b = @store.classes_hash['A::B']

    refute a.document_self, 'A is inside stopdoc'
    assert a.ignored?,      'A is inside stopdoc'

    refute a_b.document_self, 'A::B is inside stopdoc'
    assert a_b.ignored?,      'A::B is inside stopdoc'
  end

  def test_scan_struct_self_brackets
    util_parser <<-RUBY
class C < M.m
  def self.[]
  end
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'
    assert_equal %w[C::[]], c.method_list.map { |m| m.full_name }
  end

  def test_scan_visibility
    util_parser <<-RUBY
class C
   def a() end

   private :a

   class << self
     def b() end
     private :b
   end
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'

    c_a = c.find_method_named 'a'

    assert_equal :private, c_a.visibility
    refute c_a.singleton

    c_b = c.find_method_named 'b'

    assert_equal :private, c_b.visibility
    assert c_b.singleton
  end

  def test_scan_visibility_count
    util_parser <<-RUBY
class C < Original::Base
  class C2 < Original::Base
    def m0() end
    def m1() end

    private

    def m2() end
    def m3() end
    def m4() end
  end
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C::C2'

    private_method_count = c.method_list.count { |m| :private == m.visibility }
    assert_equal 3, private_method_count

    public_method_count = c.method_list.count { |m| :public == m.visibility }
    assert_equal 2, public_method_count
  end

  def test_scan_constant_visibility
    util_parser <<-RUBY
class C
   CONST_A = 123

   CONST_B = 234
   private_constant :CONST_B

   CONST_C = 345
   public_constant :CONST_C
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'
    const_a, const_b, const_c = c.constants.sort_by(&:name)

    assert_equal 'CONST_A', const_a.name
    assert_equal :public, const_a.visibility

    assert_equal 'CONST_B', const_b.name
    assert_equal :private, const_b.visibility

    assert_equal 'CONST_C', const_c.name
    assert_equal :public, const_c.visibility
  end

  def test_document_after_rescue_inside_paren
    util_parser <<-RUBY
class C
  attr_accessor :sample if (1.inexistent_method rescue false)
  # first
  # second
  def a
  end
end
    RUBY

    @parser.scan

    c = @store.find_class_named 'C'

    c_a = c.find_method_named 'a'
    assert_equal "first\nsecond", c_a.comment.text
  end

  def test_singleton_method_via_eigenclass
    util_parser <<-RUBY
class C
   class << self
     def a() end
   end
end
    RUBY

    @parser.scan

    c   = @store.find_class_named 'C'
    c_a = c.find_method_named 'a'

    assert_equal :public, c_a.visibility
    assert c_a.singleton
  end

  def test_stopdoc_after_comment
    util_parser <<-EOS
      module Bar
        # hello
        module Foo
          # :stopdoc:
        end
        # there
        class Baz
          # :stopdoc:
        end
      end
    EOS

    @parser.parse_statements @top_level

    foo = @top_level.modules.first.modules.first
    assert_equal 'Foo', foo.name
    assert_equal 'hello', foo.comment.text

    baz = @top_level.modules.first.classes.first
    assert_equal 'Baz', baz.name
    assert_equal 'there', baz.comment.text
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

  def test_parse_const_third_party
    util_parser <<-CLASS
class A
  true if B
  true if B::C
  true if B::C::D

  module B
  end
end
    CLASS

    tk = @parser.get_tk

    @parser.parse_class @top_level, RDoc::Parser::Ruby::NORMAL, tk, @comment

    a = @top_level.classes.first
    assert_equal 'A', a.full_name

    visible = @store.all_modules.reject { |mod| mod.suppressed? }
    visible = visible.map { |mod| mod.full_name }

    assert_equal ['A::B'], visible
  end

  def test_parse_const_alias_defined_elsewhere
    util_parser <<-CLASS
module A
  Aliased = Defined
end

module A
  class Defined
  end
end
    CLASS

    @parser.scan

    a = @top_level.modules.first
    assert_equal 'A', a.full_name
    aliased = a.constants.first
    assert_equal 'A::Aliased', aliased.full_name
    assert_equal [], a.modules.map(&:full_name)
    assert_equal ['A::Defined', 'A::Aliased'], a.classes.map(&:full_name)
    assert_equal ['A::Aliased'], a.constants.map(&:full_name)

    visible = @store.all_modules.reject { |mod| mod.suppressed? }
    visible = visible.map { |mod| mod.full_name }

    assert_equal ['A'], visible
  end

  def test_parse_const_alias_defined_far_away
    util_parser <<-CLASS
module A
  Aliased = ::B::C::Defined
end

module B
  module C
    class Defined
    end
  end
end
    CLASS

    @parser.scan

    a = @top_level.modules.first
    assert_equal 'A', a.full_name
    assert_empty a.classes
    assert_empty a.modules
    assert_equal ['A::Aliased'], a.constants.map(&:full_name)

    defined = @store.find_class_named 'B::C::Defined'
    assert_equal 'B::C::Defined', defined.full_name

    aliased = @store.find_class_named 'B::C::Aliased'
    assert_equal 'B::C::Aliased', aliased.full_name

    visible = @store.all_modules.reject { |mod| mod.suppressed? }
    visible = visible.map { |mod| mod.full_name }

    assert_equal ['A', 'B', 'B::C'], visible
  end

  def test_parse_include_by_dynamic_definition
    util_parser <<-CLASS
module A
  class B
    include(Module.new do
      def e(m)
      end
    end)
  end

  class C
  end

  class D
  end
end
    CLASS

    @parser.scan

    a = @store.find_module_named 'A'
    assert_equal 'A', a.full_name
    a_b = a.find_class_named 'B'
    assert_equal 'A::B', a_b.full_name
    a_c = a.find_class_named 'C'
    assert_equal 'A::C', a_c.full_name
    a_d = a.find_class_named 'D'
    assert_equal 'A::D', a_d.full_name
  end

  def test_parse_include_by_dynamic_definition_without_paren
    util_parser <<-CLASS
module A
  class B
    include(Module.new do
      def e m
      end
    end)
  end

  class C
  end

  class D
  end
end
    CLASS

    @parser.scan

    a = @store.find_module_named 'A'
    assert_equal 'A', a.full_name
    a_b = a.find_class_named 'B'
    assert_equal 'A::B', a_b.full_name
    a_c = a.find_class_named 'C'
    assert_equal 'A::C', a_c.full_name
    a_d = a.find_class_named 'D'
    assert_equal 'A::D', a_d.full_name
  end

  def test_parse_include_by_dynamic_definition_via_variable
    util_parser <<-CLASS
module A
  class B
    m = Module.new do
      def e(m)
      end
    end
    include m
  end

  class C
  end

  class D
  end
end
    CLASS

    @parser.scan

    a = @store.find_module_named 'A'
    assert_equal 'A', a.full_name
    a_b = a.find_class_named 'B'
    assert_equal 'A::B', a_b.full_name
    a_c = a.find_class_named 'C'
    assert_equal 'A::C', a_c.full_name
    a_d = a.find_class_named 'D'
    assert_equal 'A::D', a_d.full_name
  end

  def test_parse_include_by_dynamic_definition_with_brace
    util_parser <<-CLASS
module A
  class B
    extend(e {
      def f(g)
      end
    })
  end

  class C
  end

  class D
  end
end
    CLASS

    @parser.scan

    a = @store.find_module_named 'A'
    assert_equal 'A', a.full_name
    a_b = a.find_class_named 'B'
    assert_equal 'A::B', a_b.full_name
    a_c = a.find_class_named 'C'
    assert_equal 'A::C', a_c.full_name
    a_d = a.find_class_named 'D'
    assert_equal 'A::D', a_d.full_name
  end

  def test_parse_include_by_dynamic_definition_directly
    util_parser <<-CLASS
module A
  class B
    include Module.new do
      def e m
      end
    end
  end

  class C
  end

  class D
  end
end
    CLASS

    @parser.scan

    a = @store.find_module_named 'A'
    assert_equal 'A', a.full_name
    a_b = a.find_class_named 'B'
    assert_equal 'A::B', a_b.full_name
    a_c = a.find_class_named 'C'
    assert_equal 'A::C', a_c.full_name
    a_d = a.find_class_named 'D'
    assert_equal 'A::D', a_d.full_name
  end

end
