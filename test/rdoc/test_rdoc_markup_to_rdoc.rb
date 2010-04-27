require 'rubygems'
require 'rdoc/markup/formatter_test_case'
require 'rdoc/markup/to_rdoc'
require 'minitest/autorun'

class TestRDocMarkupToRdoc < RDoc::Markup::FormatterTestCase

  add_visitor_tests

  def setup
    super

    @to = RDoc::Markup::ToRdoc.new
  end

  def accept_blank_line
    assert_equal "\n", @to.res.join
  end

  def accept_heading
    assert_equal "===== Hello\n", @to.res.join
  end

  def accept_list_end_bullet
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_label
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_lalpha
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_note
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_number
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_ualpha
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_item_end_bullet
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_label
    assert_equal "\n", @to.res.join
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_lalpha
    assert_equal 0, @to.indent, 'indent'
    assert_equal 'b', @to.list_index.last
  end

  def accept_list_item_end_note
    assert_equal "\n", @to.res.join
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_number
    assert_equal 0, @to.indent, 'indent'
    assert_equal 2, @to.list_index.last
  end

  def accept_list_item_end_ualpha
    assert_equal 0, @to.indent, 'indent'
    assert_equal 'B', @to.list_index.last
  end

  def accept_list_item_start_bullet
    assert_equal [""], @to.res
    assert_equal '* ', @to.prefix
  end

  def accept_list_item_start_label
    assert_equal [""], @to.res
    assert_equal "cat:\n  ", @to.prefix

    assert_equal 2, @to.indent
  end

  def accept_list_item_start_lalpha
    assert_equal [""], @to.res
    assert_equal 'a. ', @to.prefix

    assert_equal 'a', @to.list_index.last
    assert_equal 3, @to.indent
  end

  def accept_list_item_start_note
    assert_equal [""], @to.res
    assert_equal "cat:\n  ", @to.prefix

    assert_equal 2, @to.indent
  end

  def accept_list_item_start_number
    assert_equal [""], @to.res
    assert_equal '1. ', @to.prefix

    assert_equal 1, @to.list_index.last
    assert_equal 3, @to.indent
  end

  def accept_list_item_start_ualpha
    assert_equal [""], @to.res
    assert_equal 'A. ', @to.prefix

    assert_equal 'A', @to.list_index.last
    assert_equal 3, @to.indent
  end

  def accept_list_start_bullet
    assert_equal "",   @to.res.join
    assert_equal [nil],     @to.list_index
    assert_equal [:BULLET], @to.list_type
    assert_equal [1],       @to.list_width
  end

  def accept_list_start_label
    assert_equal "",  @to.res.join
    assert_equal [nil],    @to.list_index
    assert_equal [:LABEL], @to.list_type
    assert_equal [2],      @to.list_width
  end

  def accept_list_start_lalpha
    assert_equal "",   @to.res.join
    assert_equal ['a'],     @to.list_index
    assert_equal [:LALPHA], @to.list_type
    assert_equal [1],       @to.list_width
  end

  def accept_list_start_note
    assert_equal "", @to.res.join
    assert_equal [nil],   @to.list_index
    assert_equal [:NOTE], @to.list_type
    assert_equal [2],     @to.list_width
  end

  def accept_list_start_number
    assert_equal "",   @to.res.join
    assert_equal [1],       @to.list_index
    assert_equal [:NUMBER], @to.list_type
    assert_equal [1],       @to.list_width
  end

  def accept_list_start_ualpha
    assert_equal "",   @to.res.join
    assert_equal ['A'],     @to.list_index
    assert_equal [:UALPHA], @to.list_type
    assert_equal [1],       @to.list_width
  end

  def accept_paragraph
    assert_equal "hi\n", @to.res.join
  end

  def accept_raw
    raw = <<-RAW.rstrip
<table>
<tr><th>Name<th>Count
<tr><td>a<td>1
<tr><td>b<td>2
</table>
    RAW

    assert_equal raw, @to.res.join
  end

  def accept_rule
    assert_equal "#{'-' * 78}\n", @to.res.join
  end

  def accept_verbatim # FormatterTestCase doesn't set indent for ToAnsi
    assert_equal "  hi\n  world\n\n", @to.res.join
  end

  def end_accepting
    assert_equal "hi", @to.end_accepting
  end

  def start_accepting
    assert_equal 0, @to.indent
    assert_equal [""], @to.res
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def test_accept_heading_1
    @to.start_accepting
    @to.accept_heading @RM::Heading.new(1, 'Hello')

    assert_equal "= Hello\n", @to.end_accepting
  end

  def test_accept_heading_2
    @to.start_accepting
    @to.accept_heading @RM::Heading.new(2, 'Hello')

    assert_equal "== Hello\n", @to.end_accepting
  end

  def test_accept_heading_3
    @to.start_accepting
    @to.accept_heading @RM::Heading.new(3, 'Hello')

    assert_equal "=== Hello\n", @to.end_accepting
  end

  def test_accept_heading_4
    @to.start_accepting
    @to.accept_heading @RM::Heading.new(4, 'Hello')

    assert_equal "==== Hello\n", @to.end_accepting
  end

  def test_accept_heading_indent
    @to.start_accepting
    @to.indent = 3
    @to.accept_heading @RM::Heading.new(1, 'Hello')

    assert_equal "   = Hello\n", @to.end_accepting
  end

  def test_accept_heading_b
    @to.start_accepting
    @to.indent = 3
    @to.accept_heading @RM::Heading.new(1, '*Hello*')

    assert_equal "   = <b>Hello</b>\n", @to.end_accepting
  end

  def test_accept_list_item_start_note_2
    list = @RM::List.new(:NOTE,
             @RM::ListItem.new('<tt>teletype</tt>',
                               @RM::Paragraph.new('teletype description')))

    @to.start_accepting

    list.accept @to

    expected = "<tt>teletype</tt>:\n  teletype description\n\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_b
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('reg <b>bold words</b> reg')

    expected = "reg <b>bold words</b> reg\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_i
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('reg <em>italic words</em> reg')

    expected = "reg <em>italic words</em> reg\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_indent
    @to.start_accepting
    @to.indent = 3
    @to.accept_paragraph @RM::Paragraph.new('words ' * 30)

    expected = <<-EXPECTED
   words words words words words words words words words words words words
   words words words words words words words words words words words words
   words words words words words words 
    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_plus
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('regular +teletype+ regular')

    expected = "regular <tt>teletype</tt> regular\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_star
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('regular *bold* regular')

    expected = "regular <b>bold</b> regular\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_underscore
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('regular _italic_ regular')

    expected = "regular <em>italic</em> regular\n"

    assert_equal expected, @to.end_accepting
  end

  def test_accept_paragraph_wrap
    @to.start_accepting
    @to.accept_paragraph @RM::Paragraph.new('words ' * 30)

    expected = <<-EXPECTED
words words words words words words words words words words words words words
words words words words words words words words words words words words words
words words words words 
    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def test_accept_rule_indent
    @to.start_accepting
    @to.indent = 3

    @to.accept_rule @RM::Rule.new(1)

    assert_equal "   #{'-' * 75}\n", @to.end_accepting
  end

  def test_accept_verbatim_indent
    @to.start_accepting

    @to.indent = 2

    @to.accept_verbatim @RM::Verbatim.new('    ', 'hi', "\n",
                                          '     ', 'world', "\n")

    assert_equal "    hi\n     world\n\n", @to.end_accepting
  end

  def test_accept_verbatim_big_indent
    @to.start_accepting

    @to.indent = 2

    @to.accept_verbatim @RM::Verbatim.new('    ', 'hi', "\n",
                                          '    ', 'world', "\n")

    assert_equal "    hi\n    world\n\n", @to.end_accepting
  end

  def test_attributes
    assert_equal 'Dog', @to.attributes("\\Dog")
  end

  def test_list_nested
    doc = @RM::Document.new(
            @RM::List.new(:BULLET,
              @RM::ListItem.new(nil,
                @RM::Paragraph.new('l1'),
                @RM::List.new(:BULLET,
                  @RM::ListItem.new(nil,
                    @RM::Paragraph.new('l1.1')))),
              @RM::ListItem.new(nil,
                @RM::Paragraph.new('l2'))))

    output = doc.accept @to

    expected = <<-EXPECTED
* l1
  * l1.1
* l2
    EXPECTED

    assert_equal expected, output
  end

  def test_list_verbatim # HACK overblown
    doc = @RM::Document.new(
            @RM::List.new(:BULLET,
              @RM::ListItem.new(nil,
                @RM::Paragraph.new('list', 'stuff'),
                @RM::BlankLine.new(),
                @RM::Verbatim.new('   ', '*', ' ', 'list', "\n",
                                  '     ', 'with', "\n",
                                  "\n",
                                  '     ', 'second', "\n",
                                  "\n",
                                  '     ', '1.', ' ', 'indented', "\n",
                                  '     ', '2.', ' ', 'numbered', "\n",
                                  "\n",
                                  '     ', 'third', "\n",
                                  "\n",
                                  '   ', '*', ' ', 'second', "\n"))))

    output = doc.accept @to

    expected = <<-EXPECTED
* list stuff

    * list
      with

      second

      1. indented
      2. numbered

      third

    * second

    EXPECTED

    assert_equal expected, output
  end

end

