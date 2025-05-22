# frozen_string_literal: true
require_relative 'helper'

class RDocMarkupHeadingTest < RDoc::TestCase

  def setup
    super

    @h = RDoc::Markup::Heading.new 1, 'Hello *Friend*!'
  end

  def test_aref
    assert_equal 'label-Hello+Friend-21', @h.aref
  end

  def test_label
    assert_equal 'label-Hello+Friend-21', @h.label
    assert_equal 'label-Hello+Friend-21', @h.label(nil)

    context = RDoc::NormalClass.new 'Foo'

    assert_equal 'class-Foo-label-Hello+Friend-21', @h.label(context)
  end

  def test_plain_html
    assert_equal 'Hello <strong>Friend</strong>!', @h.plain_html
  end

  def test_plain_html_using_image_alt_as_text
    h = RDoc::Markup::Heading.new 1, 'rdoc-image:foo.png:Hello World'

    assert_equal 'Hello World', h.plain_html
  end
end
