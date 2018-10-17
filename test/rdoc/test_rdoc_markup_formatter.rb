# frozen_string_literal: true
require 'minitest_helper'

class TestRDocMarkupFormatter < RDoc::TestCase

  class ToTest < RDoc::Markup::Formatter

    def initialize markup
      super nil, markup

      add_tag :TT, '<code>', '</code>'
    end

    def accept_paragraph paragraph
      @res += attributes(paragraph.text)
    end

    def attributes text
      convert_flow @am.flow text.dup
    end

    def handle_regexp_CAPS target
      "handled #{target.text}"
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
    @markup.add_regexp_handling(/[A-Z]+/, :CAPS)

    @attribute_manager = @markup.attribute_manager
    @attributes = @attribute_manager.attributes

    @to = ToTest.new @markup

    @caps            = @attributes.bitmap_for :CAPS
    @regexp_handling = @attributes.bitmap_for :_REGEXP_HANDLING_
    @tt              = @attributes.bitmap_for :TT
  end

  def test_class_gen_relative_url
    def gen(from, to)
      RDoc::Markup::ToHtml.gen_relative_url from, to
    end

    assert_equal 'a.html',    gen('a.html',   'a.html')
    assert_equal 'b.html',    gen('a.html',   'b.html')

    assert_equal 'd.html',    gen('a/c.html', 'a/d.html')
    assert_equal '../a.html', gen('a/c.html', 'a.html')
    assert_equal 'a/c.html',  gen('a.html',   'a/c.html')
  end

  def regexp_handling_names
    @attribute_manager.regexp_handlings.map do |_, mask|
      @attributes.as_string mask
    end
  end

  def test_add_regexp_handling_RDOCLINK
    @to.add_regexp_handling_RDOCLINK

    assert_includes regexp_handling_names, 'RDOCLINK'

    def @to.handle_regexp_RDOCLINK target
      "<#{target.text}>"
    end

    document = doc(para('{foo}[rdoc-label:bar].'))

    formatted = document.accept @to

    assert_equal '{foo}[<rdoc-label:bar>].', formatted
  end

  def test_add_regexp_handling_TIDYLINK
    @to.add_regexp_handling_TIDYLINK

    assert_includes regexp_handling_names, 'TIDYLINK'

    def @to.handle_regexp_TIDYLINK target
      "<#{target.text}>"
    end

    document = doc(para('foo[rdoc-label:bar].'))

    formatted = document.accept @to

    assert_equal '<foo[rdoc-label:bar]>.', formatted

    document = doc(para('{foo}[rdoc-label:bar].'))

    formatted = document.accept @to

    assert_equal '<{foo}[rdoc-label:bar]>.', formatted
  end

  def test_parse_url
    scheme, url, id = @to.parse_url 'example/foo'

    assert_equal 'http',        scheme
    assert_equal 'example/foo', url
    assert_nil   id
  end

  def test_parse_url_anchor
    scheme, url, id = @to.parse_url '#foottext-1'

    assert_nil   scheme
    assert_equal '#foottext-1', url
    assert_nil   id
  end

  def test_parse_url_link
    scheme, url, id = @to.parse_url 'link:README.txt'

    assert_equal 'link',       scheme
    assert_equal 'README.txt', url
    assert_nil   id
  end

  def test_parse_url_link_id
    scheme, url, id = @to.parse_url 'link:README.txt#label-foo'

    assert_equal 'link',                 scheme
    assert_equal 'README.txt#label-foo', url
    assert_nil   id
  end

  def test_parse_url_rdoc_label
    scheme, url, id = @to.parse_url 'rdoc-label:foo'

    assert_equal 'link', scheme
    assert_equal '#foo', url
    assert_nil   id

    scheme, url, id = @to.parse_url 'rdoc-label:foo:bar'

    assert_equal 'link',      scheme
    assert_equal '#foo',      url
    assert_equal ' id="bar"', id
  end

  def test_parse_url_scheme
    scheme, url, id = @to.parse_url 'http://example/foo'

    assert_equal 'http',               scheme
    assert_equal 'http://example/foo', url
    assert_nil   id

    scheme, url, id = @to.parse_url 'https://example/foo'

    assert_equal 'https',               scheme
    assert_equal 'https://example/foo', url
    assert_nil   id
  end

  def test_convert_tt_regexp_handling
    converted = @to.convert '<code>AAA</code>'

    assert_equal '<code>AAA</code>', converted
  end

end
