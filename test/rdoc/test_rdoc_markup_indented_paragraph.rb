require 'rdoc/test_case'

class TestRDocMarkupIndentedParagraph < RDoc::TestCase

  def setup
    super

    @IP = RDoc::Markup::IndentedParagraph
  end

  def test_initialize
    ip = @IP.new 2, 'a', 'b'

    assert_equal 2, ip.indent
    assert_equal %w[a b], ip.parts
  end

  def test_accept
    visitor = Object.new
    def visitor.accept_indented_paragraph(obj) @obj = obj end
    def visitor.obj() @obj end

    paragraph = @IP.new 0

    paragraph.accept visitor

    assert_equal paragraph, visitor.obj
  end

  def test_equals2
    one = @IP.new 1
    two = @IP.new 2

    assert_equal one, one
    refute_equal one, two
  end

  def test_text
    paragraph = @IP.new(2, 'hello', ' world')

    assert_equal 'hello world', paragraph.text
  end

  def test_text_break
    paragraph = @IP.new(2, 'hello', hard_break, 'world')

    assert_equal 'helloworld', paragraph.text

    assert_equal "hello\n  world", paragraph.text("\n")
  end

end

