require 'rubygems'
require 'minitest/autorun'
require 'rdoc'
require 'rdoc/markup'
require 'rdoc/markup/attribute_manager'

class TestAttributeManager < MiniTest::Unit::TestCase

  def setup
    @am = RDoc::Markup::AttributeManager.new
    @klass = RDoc::Markup::AttributeManager
  end

  def test_convert_attrs_ignores_code
    collector = RDoc::Markup::AttrSpan.new 10
    str = 'foo <code>__send__</code> bar'
    @am.convert_html str, collector
    @am.convert_attrs str, collector
    assert_match(/__send__/, str)
  end

  def test_convert_attrs_ignores_tt
    collector = RDoc::Markup::AttrSpan.new 10
    str = 'foo <tt>__send__</tt> bar'
    @am.convert_html str, collector
    @am.convert_attrs str, collector
    assert_match(/__send__/, str)
  end

  def test_initial_word_pairs
    word_pairs = @am.matching_word_pairs
    assert word_pairs.is_a?(Hash)
    assert_equal(3, word_pairs.size)
  end

  def test_initial_html
    html_tags = @am.html_tags
    assert html_tags.is_a?(Hash)
    assert_equal(5, html_tags.size)
  end

  def test_add_matching_word_pair
    @am.add_word_pair("x","x", :TEST)
    word_pairs = @am.matching_word_pairs
    assert_equal(4,word_pairs.size)
    assert(word_pairs.has_key?("x"))
  end

  def test_add_invalid_word_pair
    assert_raises ArgumentError do
      @am.add_word_pair("<", "<", :TEST)
    end
  end

  def test_add_word_pair_map
    @am.add_word_pair("x", "y", :TEST)
    word_pair_map = @am.word_pair_map
    assert_equal(1,word_pair_map.size)
    assert_equal(word_pair_map. keys.first.source, "(x)(\\S+)(y)")
  end

  def test_add_html_tag
    @am.add_html("Test", :TEST)
    tags = @am.html_tags
    assert_equal(6, tags.size)
    assert(tags.has_key?("test"))
  end

  def test_add_special
    @am.add_special("WikiWord", :WIKIWORD)
    specials = @am.special
    assert_equal(1,specials.size)
    assert(specials.has_key?("WikiWord"))
  end

  def silently(&block)
    warn_level = $VERBOSE
    $VERBOSE = nil
    result = block.call
    $VERBOSE = warn_level
    result
  end

end

