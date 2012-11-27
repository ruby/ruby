require 'rdoc/test_case'

class TestRDocMarkupFormatter < RDoc::TestCase

  class ToTest < RDoc::Markup::Formatter

    def initialize markup
      super nil, markup

      add_tag :TT, '<code>', '</code>'
    end

    def accept_paragraph paragraph
      @res << attributes(paragraph.text)
    end

    def attributes text
      convert_flow @am.flow text.dup
    end

    def handle_special_CAPS special
      "handled #{special.text}"
    end

    def start_accepting
      @res = ""
    end

    def end_accepting
      @res
    end

  end

  def setup
    super

    @markup = @RM.new
    @markup.add_special(/[A-Z]+/, :CAPS)

    @attribute_manager = @markup.attribute_manager
    @attributes = @attribute_manager.attributes

    @to = ToTest.new @markup

    @caps    = @attributes.bitmap_for :CAPS
    @special = @attributes.bitmap_for :_SPECIAL_
    @tt      = @attributes.bitmap_for :TT
  end

  def test_convert_tt_special
    converted = @to.convert '<code>AAA</code>'

    assert_equal '<code>AAA</code>', converted
  end

end

