require 'rdoc/test_case'

class TestRDocRdBlockParser < RDoc::TestCase

  def setup
    super

    @block_parser = RDoc::RD::BlockParser.new
  end

  def test_add_footnote
    index = @block_parser.add_footnote 'context'

    assert_equal 1, index

    expected = [
      para('{^1}[rdoc-label:footmark-1:foottext-1]', ' ', 'context'),
      blank_line,
    ]

    assert_equal expected, @block_parser.footnotes

    index = @block_parser.add_footnote 'other'

    assert_equal 2, index
  end

  def test_parse_desclist
    list = <<-LIST
:one
  desc one
:two
  desc two
    LIST

    expected =
      doc(
        list(:NOTE,
          item("one", para("desc one")),
          item("two", para("desc two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_enumlist
    list = <<-LIST
(1) one
(1) two
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil, para("one")),
          item(nil, para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_enumlist_paragraphs
    list = <<-LIST
(1) one

    two
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil,
            para("one"),
            para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_enumlist_multiline
    list = <<-LIST
(1) one
    two
    LIST

    contents = "one\n     two" # 1.8 vs 1.9

    expected =
      doc(
        list(:NUMBER,
          item(nil, para(*contents))))

    assert_equal expected, parse(list)
  end

  def test_parse_enumlist_verbatim
    list = <<-LIST
(1) item
      verbatim
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil,
            para("item"),
            verb("verbatim\n"))))

    assert_equal expected, parse(list)
  end

  def test_parse_enumlist_verbatim_continue
    list = <<-LIST
(1) one
      verbatim
    two
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil,
            para("one"),
            verb("verbatim\n"),
            para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_footnote
    expected =
      doc(
        para("{*1}[rdoc-label:foottext-1:footmark-1]"),
        rule(1),
        para("{^1}[rdoc-label:footmark-1:foottext-1]", " ", "text"),
        blank_line)

    assert_equal expected, parse("((-text-))")
  end

  def test_parse_include
    @block_parser.include_path = [Dir.tmpdir]

    expected = doc(@RM::Include.new("parse_include", [Dir.tmpdir]))

    assert_equal expected, parse("<<< parse_include")
  end

  def test_parse_include_subtree
    @block_parser.include_path = [Dir.tmpdir]

    expected =
      doc(
        blank_line,
        para("include <em>worked</em>"),
        blank_line,
        blank_line)

    tf = Tempfile.open %w[parse_include .rd] do |io|
      io.puts "=begin\ninclude ((*worked*))\n=end"
      io.flush

      str = <<-STR
<<< #{File.basename io.path}
      STR

      assert_equal expected, parse(str)
      io
    end
    tf.close! if tf.respond_to? :close!
  end

  def test_parse_heading
    assert_equal doc(head(1, "H")), parse("= H")
    assert_equal doc(head(2, "H")), parse("== H")
    assert_equal doc(head(3, "H")), parse("=== H")
    assert_equal doc(head(4, "H")), parse("==== H")
    assert_equal doc(head(5, "H")), parse("+ H")
    assert_equal doc(head(6, "H")), parse("++ H")
  end

  def test_parse_itemlist
    list = <<-LIST
* one
* two
    LIST

    expected =
      doc(
        list(:BULLET,
          item(nil, para("one")),
          item(nil, para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_itemlist_multiline
    list = <<-LIST
* one
  two
    LIST

    contents = "one\n   two" # 1.8 vs 1.9

    expected =
      doc(
        list(:BULLET,
          item(nil, para(*contents))))

    assert_equal expected, parse(list)
  end

  def test_parse_itemlist_nest
    list = <<-LIST
* one
  * inner
* two
    LIST

    expected =
      doc(
        list(:BULLET,
          item(nil,
            para("one"),
            list(:BULLET,
              item(nil, para("inner")))),
          item(nil,
            para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_itemlist_paragraphs
    list = <<-LIST
* one

  two
    LIST

    expected =
      doc(
        list(:BULLET,
          item(nil,
            para("one"),
            para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_itemlist_verbatim
    list = <<-LIST
* item
    verbatim
    LIST

    expected =
      doc(
        list(:BULLET,
          item(nil,
            para("item"),
            verb("verbatim\n"))))

    assert_equal expected, parse(list)
  end

  def test_parse_itemlist_verbatim_continue
    list = <<-LIST
* one
    verbatim
  two
    LIST

    expected =
      doc(
        list(:BULLET,
          item(nil,
            para("one"),
            verb("verbatim\n"),
            para("two"))))

    assert_equal expected, parse(list)
  end

  def test_parse_lists
    list = <<-LIST
(1) one
(1) two
* three
* four
(1) five
(1) six
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil, para("one")),
          item(nil, para("two"))),
        list(:BULLET,
          item(nil, para("three")),
          item(nil, para("four"))),
        list(:NUMBER,
          item(nil, para("five")),
          item(nil, para("six"))))

    assert_equal expected, parse(list)
  end

  def test_parse_lists_nest
    list = <<-LIST
(1) one
(1) two
      * three
      * four
(1) five
(1) six
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil, para("one")),
          item(nil,
            para("two"),
            list(:BULLET,
              item(nil, para("three")),
              item(nil, para("four")))),
          item(nil, para("five")),
          item(nil, para("six"))))

    assert_equal expected, parse(list)
  end

  def test_parse_lists_nest_verbatim
    list = <<-LIST
(1) one
(1) two
      * three
      * four
     verbatim
(1) five
(1) six
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil, para("one")),
          item(nil,
            para("two"),
            list(:BULLET,
              item(nil, para("three")),
              item(nil, para("four"))),
            verb("verbatim\n")),
          item(nil, para("five")),
          item(nil, para("six"))))

    assert_equal expected, parse(list)
  end

  def test_parse_lists_nest_verbatim2
    list = <<-LIST
(1) one
(1) two
      * three
      * four
      verbatim
(1) five
(1) six
    LIST

    expected =
      doc(
        list(:NUMBER,
          item(nil, para("one")),
          item(nil,
            para("two"),
            list(:BULLET,
              item(nil, para("three")),
              item(nil, para("four"))),
            verb("verbatim\n")),
          item(nil, para("five")),
          item(nil, para("six"))))

    assert_equal expected, parse(list)
  end

  def test_parse_methodlist
    list = <<-LIST
--- Array#each {|i| ... }
      yield block for each item.
--- Array#index(val)
      return index of first item which equals with val. if it hasn't
      same item, return nil.
    LIST

    expected =
      doc(
        list(:LABEL,
          item(
            "<tt>Array#each {|i| ... }</tt>",
            para("yield block for each item.")),
          item(
            "<tt>Array#index(val)</tt>",
            para("return index of first item which equals with val. if it hasn't same item, return nil."))))

    assert_equal expected, parse(list)
  end

  def test_parse_methodlist_empty
    list = <<-LIST
--- A#b

    LIST

    expected =
      doc(
        list(:LABEL,
          item("<tt>A#b</tt>")))

    assert_equal expected, parse(list)
  end

  def test_parse_methodlist_paragraph
    list = <<-LIST
--- A#b

    one
    LIST

    expected =
      doc(
        list(:LABEL,
          item(
            "<tt>A#b</tt>",
            para("one"))))

    assert_equal expected, parse(list)
  end

  def test_parse_methodlist_paragraph2
    list = <<-LIST.chomp
--- A#b

    one
two
    LIST

    expected =
      doc(
        list(:LABEL,
          item(
            "<tt>A#b</tt>",
            para("one"))),
        para("two"))

    assert_equal expected, parse(list)
  end

  def test_parse_methodlist_paragraph_verbatim
    list = <<-LIST.chomp
--- A#b

    text
      verbatim
    LIST

    expected =
      doc(
        list(:LABEL,
          item(
            "<tt>A#b</tt>",
            para("text"),
            verb("verbatim\n"))))

    assert_equal expected, parse(list)
  end

  def test_parse_verbatim
    assert_equal doc(verb("verbatim\n")), parse("  verbatim")
  end

  def test_parse_verbatim_blankline
    expected = doc(verb("one\n", "\n", "two\n"))

    verbatim = <<-VERBATIM
  one

  two
    VERBATIM

    assert_equal expected, parse(verbatim)
  end

  def test_parse_verbatim_indent
    expected = doc(verb("one\n", " two\n"))

    verbatim = <<-VERBATIM
  one
   two
    VERBATIM

    assert_equal expected, parse(verbatim)
  end

  def test_parse_verbatim_multi
    expected = doc(verb("one\n", "two\n"))

    verbatim = <<-VERBATIM
  one
  two
    VERBATIM

    assert_equal expected, parse(verbatim)
  end

  def test_parse_textblock
    assert_equal doc(para("text")), parse("text")
  end

  def test_parse_textblock_multi
    expected = doc(para("one two"))

    assert_equal expected, parse("one\ntwo")
  end

  def parse text
    text = ["=begin", text, "=end"].join "\n"

    doc = @block_parser.parse text.lines.to_a

    assert_equal blank_line, doc.parts.shift, "=begin blankline"
    assert_equal blank_line, doc.parts.pop, "=end blankline"

    doc
  end

end
