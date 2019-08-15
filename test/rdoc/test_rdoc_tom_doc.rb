# frozen_string_literal: true
require 'minitest_helper'

class TestRDocTomDoc < RDoc::TestCase

  def setup
    super

    @top_level = @store.add_file 'file.rb'

    @TD = RDoc::TomDoc
    @td = @TD.new
  end

  def test_class_add_post_processor
    RDoc::TomDoc.add_post_processor

    pp = RDoc::Markup::PreProcess.new __FILE__, []

    text = "# Public: Do some stuff\n"

    comment = RDoc::Comment.new text, nil
    comment.format = 'tomdoc'

    parent = RDoc::Context.new

    pp.handle comment, parent

    method = parent.add_method RDoc::AnyMethod.new(nil, 'm')

    assert_equal 'Public', method.section.title
    assert_equal "# Do some stuff\n", comment.text
  end

  def test_class_signature
    c = comment <<-COMMENT
Signature

  method_<here>(args)

here - something
    COMMENT
    c.format = 'tomdoc'

    signature = @TD.signature c

    assert_equal "method_<here>(args)\n", signature
  end

  def test_class_signature_no_space
    c = comment <<-COMMENT
Signature
  method_<here>(args)

here - something
    COMMENT
    c.format = 'tomdoc'

    signature = @TD.signature c

    assert_equal "method_<here>(args)\n", signature

    expected =
      doc(
        head(3, 'Signature'),
        list(:NOTE,
          item(%w[here],
            para('something'))))
    expected.file = @top_level

    assert_equal expected, c.parse
  end

  def test_class_signature_none
    c = comment ''
    c.format = 'tomdoc'

    assert_nil @TD.signature c
  end

  def test_class_rdoc
    c = comment <<-COMMENT
=== Signature

  method_<here>(args)

here - something
    COMMENT
    c.format = 'rdoc'

    signature = @TD.signature c

    assert_nil signature
  end

  def test_class_signature_two_space
    c = comment <<-COMMENT
Signature


  method_<here>(args)

here - something
    COMMENT
    c.format = 'tomdoc'

    signature = @TD.signature c

    assert_equal "method_<here>(args)\n", signature

    expected =
      doc(
        head(3, 'Signature'),
        list(:NOTE,
          item(%w[here],
            para('something'))))
    expected.file = @top_level

    assert_equal expected, c.parse
  end

  def test_parse_paragraph
    text = "Public: Do some stuff\n"

    expected =
      @RM::Document.new(
        @RM::Paragraph.new('Do some stuff'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_multiline_paragraph
    text = "Public: Do some stuff\n"
    text += "On a new line\n"

    expected =
      doc(
        para('Do some stuff', ' ', 'On a new line'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_arguments
    text = <<-TEXT
Create new Arg object.

name        - name of argument
description - arguments description
    TEXT

    expected =
      doc(
        para('Create new Arg object.'),
        blank_line,
        list(:NOTE,
          item(%w[name],
            para('name of argument')),
          item(%w[description],
            para('arguments description'))))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_arguments_array
    text = <<-TEXT
Create new Arg object.

names[] - names of arguments
    TEXT

    expected =
      doc(
        para('Create new Arg object.'),
        blank_line,
        list(:NOTE,
          item(%w[names[]],
            para('names of arguments'))))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_arguments_multiline
    text = <<-TEXT
Do some stuff

foo - A comment goes here
  and is more than one line
    TEXT

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        list(:NOTE,
          item(%w[foo],
            para('A comment goes here', ' ', 'and is more than one line'))))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_arguments_nested
    text = <<-TEXT
Do some stuff

foo - A comment goes here
      :bar - bar documentation
    TEXT

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        list(:NOTE,
          item(%w[foo],
            para('A comment goes here'),
            list(:NOTE,
              item(%w[:bar],
                para('bar documentation'))))))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_examples
    text = <<-TEXT
Do some stuff

Examples

  1 + 1
    TEXT

    code = verb("1 + 1\n")
    code.format = :ruby

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Examples'),
        blank_line,
        code)

    document = @TD.parse(text)
    assert_equal expected, document
    assert document.parts.last.ruby?
  end

  def test_parse_examples_signature
    text = <<-TEXT
Do some stuff

Examples

  1 + 1

Signature

  foo(args)
    TEXT

    code1 = verb("1 + 1\n")
    code1.format = :ruby

    code2 = verb("foo(args)\n")

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Examples'),
        blank_line,
        code1,
        head(3, 'Signature'),
        blank_line,
        code2)

    document = @TD.parse text

    assert_equal expected, document
  end

  def test_parse_returns
    text = <<-TEXT
Do some stuff

Returns a thing

Returns another thing
    TEXT

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Returns'),
        blank_line,
        para('Returns a thing'),
        blank_line,
        para('Returns another thing'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_returns_with_raises
    text = <<-TEXT
Do some stuff

Returns a thing
Raises ArgumentError when stuff
Raises StandardError when stuff
    TEXT
    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Returns'),
        blank_line,
        para('Returns a thing'),
        para('Raises ArgumentError when stuff'),
        para('Raises StandardError when stuff'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_raises_without_returns
    text = <<-TEXT
Do some stuff

Raises ArgumentError when stuff
    TEXT
    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Returns'),
        blank_line,
        para('Raises ArgumentError when stuff'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_returns_multiline
    text = <<-TEXT
Do some stuff

Returns a thing
  that is multiline
    TEXT

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Returns'),
        blank_line,
        para('Returns a thing', ' ', 'that is multiline'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_returns_multiline_and_raises
    text = <<-TEXT
Do some stuff

Returns a thing
  that is multiline
Raises ArgumentError
    TEXT

    expected =
      doc(
        para('Do some stuff'),
        blank_line,
        head(3, 'Returns'),
        blank_line,
        para('Returns a thing', ' ', 'that is multiline'),
        para('Raises ArgumentError'))

    assert_equal expected, @TD.parse(text)
  end

  def test_parse_signature
    text = <<-TEXT
Do some stuff

Signature

  some_method(args)
    TEXT

    expected =
      @RM::Document.new(
        @RM::Paragraph.new('Do some stuff'),
        @RM::BlankLine.new,
        @RM::Heading.new(3, 'Signature'),
        @RM::BlankLine.new,
        @RM::Verbatim.new("some_method(args)\n"))

    assert_equal expected, @TD.parse(text)
  end

  def test_tokenize_paragraph
    @td.tokenize "Public: Do some stuff\n"

    expected = [
      [:TEXT,    "Do some stuff",  0, 0],
      [:NEWLINE, "\n",            13, 0],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_multiline_paragraph
    text = "Public: Do some stuff\n"
    text += "On a new line\n"

    @td.tokenize text

    expected = [
      [:TEXT,     "Do some stuff",   0, 0],
      [:NEWLINE,  "\n",             13, 0],
      [:TEXT,     "On a new line",   0, 1],
      [:NEWLINE,  "\n",             13, 1]
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_arguments
    @td.tokenize <<-TEXT
Create new Arg object.

name        - name of argument
description - arguments description
    TEXT

    expected = [
      [:TEXT,    "Create new Arg object.",  0, 0],
      [:NEWLINE, "\n",                     22, 0],
      [:NEWLINE, "\n",                      0, 1],
      [:NOTE,    "name",                    0, 2],
      [:TEXT,    "name of argument",       14, 2],
      [:NEWLINE, "\n",                     30, 2],
      [:NOTE,    "description",             0, 3],
      [:TEXT,    "arguments description",  14, 3],
      [:NEWLINE, "\n",                     35, 3],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_arguments_array
    @td.tokenize <<-TEXT
Create new Arg object.

names[stuff] - names of arguments
    TEXT

    expected = [
      [:TEXT,    "Create new Arg object.",  0, 0],
      [:NEWLINE, "\n",                     22, 0],
      [:NEWLINE, "\n",                      0, 1],
      [:NOTE,    "names[stuff]",            0, 2],
      [:TEXT,    "names of arguments",     15, 2],
      [:NEWLINE, "\n",                     33, 2],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_arguments_multiline
    @td.tokenize <<-TEXT
Do some stuff

foo - A comment goes here
  and is more than one line
    TEXT

    expected = [
      [:TEXT,    "Do some stuff",              0, 0],
      [:NEWLINE, "\n",                        13, 0],
      [:NEWLINE, "\n",                         0, 1],
      [:NOTE,    "foo",                        0, 2],
      [:TEXT,    "A comment goes here",        6, 2],
      [:NEWLINE, "\n",                        25, 2],
      [:TEXT,    "and is more than one line",  2, 3],
      [:NEWLINE, "\n",                        27, 3],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_arguments_nested
    @td.tokenize <<-TEXT
Do some stuff

foo - A comment goes here
      :bar - bar documentation
    TEXT

    expected = [
      [:TEXT,    "Do some stuff",              0, 0],
      [:NEWLINE, "\n",                        13, 0],
      [:NEWLINE, "\n",                         0, 1],
      [:NOTE,    "foo",                        0, 2],
      [:TEXT,    "A comment goes here",        6, 2],
      [:NEWLINE, "\n",                        25, 2],
      [:NOTE,    ":bar",                       6, 3],
      [:TEXT,    "bar documentation",         13, 3],
      [:NEWLINE, "\n",                        30, 3],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_examples
    @td.tokenize <<-TEXT
Do some stuff

Examples

  1 + 1
    TEXT

    expected = [
      [:TEXT,    "Do some stuff",  0, 0],
      [:NEWLINE, "\n",            13, 0],
      [:NEWLINE, "\n",             0, 1],
      [:HEADER,  3,                0, 2],
      [:TEXT,    "Examples",       0, 2],
      [:NEWLINE, "\n",             8, 2],
      [:NEWLINE, "\n",             0, 3],
      [:TEXT,    "1 + 1",          2, 4],
      [:NEWLINE, "\n",             7, 4],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_returns
    @td.tokenize <<-TEXT
Do some stuff

Returns a thing
    TEXT

    expected = [
      [:TEXT,    "Do some stuff",    0, 0],
      [:NEWLINE, "\n",              13, 0],
      [:NEWLINE, "\n",               0, 1],
      [:TEXT,    "Returns a thing",  0, 2],
      [:NEWLINE, "\n",              15, 2],
    ]

    assert_equal expected, @td.tokens
  end

  def test_tokenize_returns_multiline
    @td.tokenize <<-TEXT
Do some stuff

Returns a thing
  that is multiline
    TEXT

    expected = [
      [:TEXT,    "Do some stuff",      0, 0],
      [:NEWLINE, "\n",                13, 0],
      [:NEWLINE, "\n",                 0, 1],
      [:TEXT,    "Returns a thing",    0, 2],
      [:NEWLINE, "\n",                15, 2],
      [:TEXT,    "that is multiline",  2, 3],
      [:NEWLINE, "\n",                19, 3],
    ]

    assert_equal expected, @td.tokens
  end

end
