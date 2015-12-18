# frozen_string_literal: false
require 'rdoc/test_case'

class TestRDocMarkupParagraph < RDoc::TestCase

  def test_accept
    visitor = Object.new
    def visitor.accept_paragraph(obj) @obj = obj end
    def visitor.obj() @obj end

    paragraph = RDoc::Markup::Paragraph.new

    paragraph.accept visitor

    assert_same paragraph, visitor.obj
  end

  def test_text
    paragraph = para('hello', ' world')

    assert_equal 'hello world', paragraph.text
  end

  def test_text_break
    paragraph = para('hello', hard_break, 'world')

    assert_equal 'helloworld', paragraph.text

    assert_equal "hello\nworld", paragraph.text("\n")
  end

end

