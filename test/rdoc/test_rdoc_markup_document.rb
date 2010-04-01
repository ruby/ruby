require 'pp'
require 'rubygems'
require 'minitest/autorun'
require 'rdoc/markup'

class TestRDocMarkupDocument < MiniTest::Unit::TestCase

  def setup
    @RM = RDoc::Markup
    @d = @RM::Document.new
  end

  def mu_pp obj
    s = ''
    s = PP.pp obj, s
    s.force_encoding Encoding.default_external if defined? Encoding
    s.chomp
  end

  def test_append
    @d << @RM::Paragraph.new('hi')

    expected = @RM::Document.new @RM::Paragraph.new('hi')

    assert_equal expected, @d
  end

  def test_append_document
    @d << @RM::Document.new

    assert_empty @d

    @d << @RM::Document.new(@RM::Paragraph.new('hi'))

    expected = @RM::Document.new @RM::Paragraph.new('hi'), @RM::BlankLine.new

    assert_equal expected, @d
  end

  def test_append_string
    @d << ''

    assert_empty @d

    assert_raises ArgumentError do
      @d << 'hi'
    end
  end

end

