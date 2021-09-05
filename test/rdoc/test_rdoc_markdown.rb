# coding: UTF-8
# frozen_string_literal: true

require_relative 'helper'
require 'rdoc/markup/block_quote'
require 'rdoc/markdown'

class TestRDocMarkdown < RDoc::TestCase

  def setup
    super

    @RM = RDoc::Markup

    @parser = RDoc::Markdown.new

    @to_html = RDoc::Markup::ToHtml.new(RDoc::Options.new, nil)
  end

  def test_class_parse
    doc = RDoc::Markdown.parse "hello\n\nworld"

    expected = doc(para("hello"), para("world"))

    assert_equal expected, doc
  end

  def test_emphasis
    assert_equal '_word_',             @parser.emphasis('word')
    assert_equal '<em>two words</em>', @parser.emphasis('two words')
    assert_equal '<em>*bold*</em>',    @parser.emphasis('*bold*')
  end

  def test_parse_auto_link_email
    doc = parse "Autolink: <nobody-0+_./!%~$@example>"

    expected = doc(para("Autolink: mailto:nobody-0+_./!%~$@example"))

    assert_equal expected, doc
  end

  def test_parse_auto_link_url
    doc = parse "Autolink: <http://example>"

    expected = doc(para("Autolink: http://example"))

    assert_equal expected, doc
  end

  def test_parse_block_quote
    doc = parse <<-BLOCK_QUOTE
> this is
> a block quote
    BLOCK_QUOTE

    expected =
      doc(
        block(
          para("this is\na block quote")))

    assert_equal expected, doc
  end

  def test_parse_block_quote_continue
    doc = parse <<-BLOCK_QUOTE
> this is
a block quote
    BLOCK_QUOTE

    expected =
      doc(
        block(
          para("this is\na block quote")))

    assert_equal expected, doc
  end

  def test_parse_block_quote_list
    doc = parse <<-BLOCK_QUOTE
> text
>
> * one
> * two
    BLOCK_QUOTE

    expected =
      doc(
        block(
          para("text"),
          list(:BULLET,
            item(nil, para("one")),
            item(nil, para("two")))))

    assert_equal expected, doc
  end

  def test_parse_block_quote_newline
    doc = parse <<-BLOCK_QUOTE
> this is
a block quote

    BLOCK_QUOTE

    expected =
      doc(
        block(
          para("this is\na block quote")))

    assert_equal expected, doc
  end

  def test_parse_block_quote_separate
    doc = parse <<-BLOCK_QUOTE
> this is
a block quote

> that continues
    BLOCK_QUOTE

    expected =
      doc(
        block(
          para("this is\na block quote"),
          para("that continues")))

    assert_equal expected, doc
  end

  def test_parse_char_entity
    doc = parse '&pi; &nn;'

    expected = doc(para('π &nn;'))

    assert_equal expected, doc
  end

  def test_parse_code
    doc = parse "Code: `text`"

    expected = doc(para("Code: <code>text</code>"))

    assert_equal expected, doc
  end

  def test_parse_code_github
    doc = <<-MD
Example:

```
code goes here
```
    MD

    expected =
      doc(
        para("Example:"),
        verb("code goes here\n"))

    assert_equal expected, parse(doc)
    assert_equal expected, parse(doc.sub(/^\n/, ''))

    @parser.github = false

    expected =
      doc(para("Example:"),
          para("<code>\n""code goes here\n</code>"))

    assert_equal expected, parse(doc)

    expected =
      doc(para("Example:\n<code>\n""code goes here\n</code>"))

    assert_equal expected, parse(doc.sub(/^\n/, ''))
  end

  def test_parse_code_github_format
    doc = <<-MD
Example:

``` ruby
code goes here
```
    MD

    code = verb("code goes here\n")
    code.format = :ruby

    expected =
      doc(
        para("Example:"),
        code)

    assert_equal expected, parse(doc)
    assert_equal expected, parse(doc.sub(/^\n/, ''))

    @parser.github = false

    expected =
      doc(para("Example:"),
          para("<code>ruby\n""code goes here\n</code>"))

    assert_equal expected, parse(doc)

    expected =
      doc(para("Example:\n<code>ruby\n""code goes here\n</code>"))

    assert_equal expected, parse(doc.sub(/^\n/, ''))
  end

  def test_parse_definition_list
    doc = parse <<-MD
one
:   This is a definition

two
:   This is another definition
    MD

    expected = doc(
      list(:NOTE,
        item(%w[one], para("This is a definition")),
        item(%w[two], para("This is another definition"))))

    assert_equal expected, doc
  end

  def test_parse_definition_list_indents
    doc = parse <<-MD
zero
: Indented zero characters

one
 : Indented one characters

two
  : Indented two characters

three
   : Indented three characters

four
    : Indented four characters

    MD

    expected = doc(
      list(:NOTE,
        item(%w[zero],  para("Indented zero characters")),
        item(%w[one],   para("Indented one characters")),
        item(%w[two],   para("Indented two characters")),
        item(%w[three], para("Indented three characters"))),
      para("four\n : Indented four characters"))

    assert_equal expected, doc
  end

  def test_parse_definition_list_multi_description
    doc = parse <<-MD
label
:   This is a definition

:   This is another definition
    MD

    expected = doc(
      list(:NOTE,
        item(%w[label], para("This is a definition")),
        item(nil,       para("This is another definition"))))

    assert_equal expected, doc
  end

  def test_parse_definition_list_multi_label
    doc = parse <<-MD
one
two
:   This is a definition
    MD

    expected = doc(
      list(:NOTE,
        item(%w[one two], para("This is a definition"))))

    assert_equal expected, doc
  end

  def test_parse_definition_list_multi_line
    doc = parse <<-MD
one
:   This is a definition
that extends to two lines

two
:   This is another definition
that also extends to two lines
    MD

    expected = doc(
      list(:NOTE,
        item(%w[one],
          para("This is a definition\nthat extends to two lines")),
        item(%w[two],
          para("This is another definition\nthat also extends to two lines"))))

    assert_equal expected, doc
  end

  def test_parse_definition_list_no
    @parser.definition_lists = false

    doc = parse <<-MD
one
:   This is a definition

two
:   This is another definition
    MD

    expected = doc(
        para("one\n: This is a definition"),
        para("two\n: This is another definition"))

    assert_equal expected, doc
  end

  def test_parse_entity_dec
    doc = parse "Entity: &#65;"

    expected = doc(para("Entity: A"))

    assert_equal expected, doc
  end

  def test_parse_entity_hex
    doc = parse "Entity: &#x41;"

    expected = doc(para("Entity: A"))

    assert_equal expected, doc
  end

  def test_parse_entity_named
    doc = parse "Entity: &pi;"

    expected = doc(para("Entity: π"))

    assert_equal expected, doc
  end

  def test_parse_emphasis_star
    doc = parse "it *works*\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it _works_"))

    assert_equal expected, doc
  end

  def test_parse_emphasis_underscore
    doc = parse "it _works_\n"

    expected =
      doc(
        para("it _works_"))

    assert_equal expected, doc
  end

  def test_parse_emphasis_underscore_embedded
    doc = parse "foo_bar bar_baz\n"

    expected =
      doc(
        para("foo_bar bar_baz"))

    assert_equal expected, doc
  end

  def test_parse_emphasis_underscore_in_word
    doc = parse "it foo_bar_baz\n"

    expected =
      doc(
        para("it foo_bar_baz"))

    assert_equal expected, doc
  end

  def test_parse_escape
    assert_equal doc(para("Backtick: `")), parse("Backtick: \\`")

    assert_equal doc(para("Backslash: \\")), parse("Backslash: \\\\")

    assert_equal doc(para("Colon: :")), parse("Colon: \\:")
  end

  def test_parse_heading_atx
    doc = parse "# heading\n"

    expected = @RM::Document.new(
      @RM::Heading.new(1, "heading"))

    assert_equal expected, doc
  end

  def test_parse_heading_setext_dash
    doc = parse <<-MD
heading
---
    MD

    expected = @RM::Document.new(
      @RM::Heading.new(2, "heading"))

    assert_equal expected, doc
  end

  def test_parse_heading_setext_equals
    doc = parse <<-MD
heading
===
    MD

    expected = @RM::Document.new(
      @RM::Heading.new(1, "heading"))

    assert_equal expected, doc
  end

  def test_parse_html
    @parser.html = true

    doc = parse "<address>Links here</address>\n"

    expected = doc(
      @RM::Raw.new("<address>Links here</address>"))

    assert_equal expected, doc
  end

  def test_parse_html_hr
    @parser.html = true

    doc = parse "<hr>\n"

    expected = doc(raw("<hr>"))

    assert_equal expected, doc
  end

  def test_parse_html_no_html
    @parser.html = false

    doc = parse "<address>Links here</address>\n"

    expected = doc()

    assert_equal expected, doc
  end

  def test_parse_image
    doc = parse "image ![alt text](path/to/image.jpg)"

    expected = doc(para("image rdoc-image:path/to/image.jpg"))

    assert_equal expected, doc
  end

  def test_parse_image_link
    @parser.html = true

    doc = parse "[![alt text](path/to/image.jpg)](http://example.com)"

    expected =
      doc(
        para('{rdoc-image:path/to/image.jpg}[http://example.com]'))

    assert_equal expected, doc
  end

  def test_parse_line_break
    doc = parse "Some text  \nwith extra lines"

    expected = doc(
      para("Some text", hard_break, "with extra lines"))

    assert_equal expected, doc
  end

  def test_parse_link_reference_id
    doc = parse <<-MD
This is [an example][id] reference-style link.

[id]: http://example.com "Optional Title Here"
    MD

    expected = doc(
      para("This is {an example}[http://example.com] reference-style link."))

    assert_equal expected, doc
  end

  def test_parse_link_reference_id_adjacent
    doc = parse <<-MD
[this] [this] should work

[this]: example
    MD

    expected = doc(
      para("{this}[example] should work"))

    assert_equal expected, doc
  end

  def test_parse_link_reference_id_eof
    doc = parse <<-MD.chomp
This is [an example][id] reference-style link.

[id]: http://example.com "Optional Title Here"
    MD

    expected = doc(
      para("This is {an example}[http://example.com] reference-style link."))

    assert_equal expected, doc
  end

  def test_parse_link_reference_id_many
    doc = parse <<-MD
This is [an example][id] reference-style link.

And [another][id].

[id]: http://example.com "Optional Title Here"
    MD

    expected = doc(
      para("This is {an example}[http://example.com] reference-style link."),
      para("And {another}[http://example.com]."))

    assert_equal expected, doc
  end

  def test_parse_link_reference_implicit
    doc = parse <<-MD
This is [an example][] reference-style link.

[an example]: http://example.com "Optional Title Here"
    MD

    expected = doc(
      para("This is {an example}[http://example.com] reference-style link."))

    assert_equal expected, doc
  end

  def test_parse_list_bullet
    doc = parse <<-MD
* one
* two
    MD

    expected = doc(
      list(:BULLET,
        item(nil, para("one")),
        item(nil, para("two"))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_auto_link
    doc = parse <<-MD
* <http://example/>
    MD

    expected = doc(
      list(:BULLET,
        item(nil, para("http://example/"))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_continue
    doc = parse <<-MD
* one

* two
    MD

    expected = doc(
      list(:BULLET,
        item(nil, para("one")),
        item(nil, para("two"))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_multiline
    doc = parse <<-MD
* one
  two
    MD

    expected = doc(
      list(:BULLET,
        item(nil, para("one\n two"))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_nest
    doc = parse <<-MD
* outer
    * inner
    MD

    expected = doc(
      list(:BULLET,
        item(nil,
          para("outer"),
          list(:BULLET,
            item(nil,
              para("inner"))))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_nest_loose
    doc = parse <<-MD
* outer

    * inner
    MD

    expected = doc(
      list(:BULLET,
        item(nil,
          para("outer"),
          list(:BULLET,
            item(nil, para("inner"))))))

    assert_equal expected, doc
  end

  def test_parse_list_bullet_nest_continue
    doc = parse <<-MD
* outer
    * inner
  continue inner
* outer 2
    MD

    expected = doc(
      list(:BULLET,
        item(nil,
          para("outer"),
          list(:BULLET,
            item(nil,
              para("inner\n continue inner")))),
        item(nil,
          para("outer 2"))))

    assert_equal expected, doc
  end

  def test_parse_list_number
    doc = parse <<-MD
1. one
1. two
    MD

    expected = doc(
      list(:NUMBER,
        item(nil, para("one")),
        item(nil, para("two"))))

    assert_equal expected, doc
  end

  def test_parse_list_number_continue
    doc = parse <<-MD
1. one

1. two
    MD

    expected = doc(
      list(:NUMBER,
        item(nil, para("one")),
        item(nil, para("two"))))

    assert_equal expected, doc
  end

  def test_parse_note
    @parser.notes = true

    doc = parse <<-MD
Some text.[^1]

[^1]: With a footnote
    MD

    expected = doc(
      para("Some text.{*1}[rdoc-label:foottext-1:footmark-1]"),
      @RM::Rule.new(1),
      para("{^1}[rdoc-label:footmark-1:foottext-1] With a footnote"))

    assert_equal expected, doc
  end

  def test_parse_note_indent
    @parser.notes = true

    doc = parse <<-MD
Some text.[^1]

[^1]: With a footnote

    more
    MD

    expected = doc(
      para("Some text.{*1}[rdoc-label:foottext-1:footmark-1]"),
      rule(1),
      para("{^1}[rdoc-label:footmark-1:foottext-1] With a footnote\n\nmore"))

    assert_equal expected, doc
  end

  def test_parse_note_inline
    @parser.notes = true

    doc = parse <<-MD
Some text. ^[With a footnote]
    MD

    expected = doc(
      para("Some text. {*1}[rdoc-label:foottext-1:footmark-1]"),
      @RM::Rule.new(1),
      para("{^1}[rdoc-label:footmark-1:foottext-1] With a footnote"))

    assert_equal expected, doc
  end

  def test_parse_note_no_notes
    @parser.notes = false

    assert_raise RDoc::Markdown::ParseError do
      parse "Some text.[^1]"
    end
  end

  def test_parse_note_multiple
    @parser.notes = true

    doc = parse <<-MD
Some text[^1]
with inline notes^[like this]
and an extra note.[^2]

[^1]: With a footnote

[^2]: Which should be numbered correctly
    MD

    expected = doc(
      para("Some text{*1}[rdoc-label:foottext-1:footmark-1]\n" +
           "with inline notes{*2}[rdoc-label:foottext-2:footmark-2]\n" +
           "and an extra note.{*3}[rdoc-label:foottext-3:footmark-3]"),

      rule(1),

      para("{^1}[rdoc-label:footmark-1:foottext-1] With a footnote"),
      para("{^2}[rdoc-label:footmark-2:foottext-2] like this"),
      para("{^3}[rdoc-label:footmark-3:foottext-3] " +
           "Which should be numbered correctly"))

    assert_equal expected, doc
  end

  def test_parse_paragraph
    doc = parse "it worked\n"

    expected = doc(para("it worked"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_break_on_newline
    @parser.break_on_newline = true

    doc = parse "one\ntwo\n"

    expected = doc(para("one", hard_break, "two"))

    assert_equal expected, doc

    doc = parse "one  \ntwo\nthree\n"

    expected = doc(para("one", hard_break, "two", hard_break, "three"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_stars
    doc = parse "it worked ****\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it worked ****"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_html
    @parser.html = true

    doc = parse "<address>Links here</address>"

    expected = doc(raw("<address>Links here</address>"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_html_no_html
    @parser.html = false

    doc = parse "<address>Links here</address>"

    expected = doc()

    assert_equal expected, doc
  end

  def test_parse_paragraph_indent_one
    doc = parse <<-MD
 text
    MD

    expected = doc(para("text"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_indent_two
    doc = parse <<-MD
  text
    MD

    expected = doc(para("text"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_indent_three
    doc = parse <<-MD
   text
    MD

    expected = doc(para("text"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_multiline
    doc = parse "one\ntwo"

    expected = doc(para("one\ntwo"))

    assert_equal expected, doc
  end

  def test_parse_paragraph_two
    doc = parse "one\n\ntwo"

    expected = @RM::Document.new(
      @RM::Paragraph.new("one"),
      @RM::Paragraph.new("two"))

    assert_equal expected, doc
  end

  def test_parse_plain
    doc = parse "it worked"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it worked"))

    assert_equal expected, doc
  end

  def test_parse_reference_link_embedded_bracket
    doc = parse "With [embedded [brackets]] [b].\n\n[b]: /url/\n"

    expected =
      doc(
        para("With {embedded [brackets]}[/url/]."))

    assert_equal expected, doc
  end

  def test_parse_rule_dash
    doc = parse "- - -\n\n"

    expected = @RM::Document.new(@RM::Rule.new(1))

    assert_equal expected, doc
  end

  def test_parse_rule_underscore
    doc = parse "_ _ _\n\n"

    expected = @RM::Document.new(@RM::Rule.new(1))

    assert_equal expected, doc
  end

  def test_parse_rule_star
    doc = parse "* * *\n\n"

    expected = @RM::Document.new(@RM::Rule.new(1))

    assert_equal expected, doc
  end

  def test_parse_strong_star
    doc = parse "it **works**\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it *works*"))

    assert_equal expected, doc
  end

  def test_parse_strong_underscore
    doc = parse "it __works__\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it *works*"))

    assert_equal expected, doc
  end

  def test_parse_strong_emphasis_star
    doc = parse "it ***works***\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it <b>_works_</b>"))

    assert_equal expected, doc
  end

  def test_parse_strong_emphasis_underscore
    doc = parse "it ___works___\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it <b>_works_</b>"))

    assert_equal expected, doc
  end

  def test_parse_strike_tilde
    doc = parse "it ~~works~~\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it ~works~"))

    assert_equal expected, doc
  end

  def test_parse_strike_words_tilde
    doc = parse "it ~~works fine~~\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it <s>works fine</s>"))

    assert_equal expected, doc
  end

  def test_parse_strike_tilde_no
    @parser.strike = false

    doc = parse "it ~~works fine~~\n"

    expected = @RM::Document.new(
      @RM::Paragraph.new("it ~~works fine~~"))

    assert_equal expected, doc
  end

  def test_parse_style
    @parser.css = true

    doc = parse "<style>h1 { color: red }</style>\n"

    expected = doc(
      @RM::Raw.new("<style>h1 { color: red }</style>"))

    assert_equal expected, doc
  end

  def test_parse_style_disabled
    doc = parse "<style>h1 { color: red }</style>\n"

    expected = doc()

    assert_equal expected, doc
  end

  def test_parse_verbatim
    doc = parse <<-MD
    text
    MD

    expected = doc(verb("text\n"))

    assert_equal expected, doc
  end

  def test_parse_verbatim_eof
    doc = parse "    text"

    expected = doc(verb("text\n"))

    assert_equal expected, doc
  end

  def test_strong
    assert_equal '*word*',            @parser.strong('word')
    assert_equal '<b>two words</b>',  @parser.strong('two words')
    assert_equal '<b>_emphasis_</b>', @parser.strong('_emphasis_')
  end

  def test_code_fence_with_unintended_array
    doc = parse '```<ruby>```'

    expected = doc(verb('<ruby>'))

    assert_equal expected, doc
  end

  def test_gfm_table
    doc = parse <<~MD
    |      |                 |compare-ruby|built-ruby|
    |------|:----------------|-----------:|---------:|
    |test  | 1               |     11.618M|   10.757M|
    |      |                 |       1.08x|         -|
    |test  | 10              |      1.849M|    1.723M|
    |      |                 |       1.07x|         -|
    MD

    head = ["", "", "compare-ruby", "built-ruby"]
    align = [nil, :left, :right, :right]
    body = [
      ["test", "1", "11.618M", "10.757M"],
      ["", "", "1.08x", "-"],
      ["test", "10", "1.849M", "1.723M"],
      ["", "", "1.07x", "-"],
    ]
    expected = doc(@RM::Table.new(head, align, body))

    assert_equal expected, doc
  end

  def parse text
    @parser.parse text
  end

end

