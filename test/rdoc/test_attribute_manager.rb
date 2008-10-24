require 'rubygems'
require 'minitest/unit'
require 'rdoc/markup/attribute_manager'

class TestAttributeManager < MiniTest::Unit::TestCase

  def setup
    @am = RDoc::Markup::AttributeManager.new
    @klass = RDoc::Markup::AttributeManager
  end

  def teardown
    silently do
      @klass.const_set(:MATCHING_WORD_PAIRS, {})
      @klass.const_set(:WORD_PAIR_MAP, {})
      @klass.const_set(:HTML_TAGS, {})
    end
  end

  def test_initial_word_pairs
    word_pairs = @klass::MATCHING_WORD_PAIRS
    assert word_pairs.is_a?(Hash)
    assert_equal(3, word_pairs.size)
  end

  def test_initial_html
    html_tags = @klass::HTML_TAGS
    assert html_tags.is_a?(Hash)
    assert_equal(5, html_tags.size)
  end

  def test_add_matching_word_pair
    @am.add_word_pair("x","x", :TEST)
    word_pairs = @klass::MATCHING_WORD_PAIRS
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
    word_pair_map = @klass::WORD_PAIR_MAP
    assert_equal(1,word_pair_map.size)
    assert_equal(word_pair_map. keys.first.source, "(x)(\\S+)(y)")
  end

  def test_add_html_tag
    @am.add_html("Test", :TEST)
    tags = @klass::HTML_TAGS
    assert_equal(6, tags.size)
    assert(tags.has_key?("test"))
  end

  def test_add_special
    @am.add_special("WikiWord", :WIKIWORD)
    specials = @klass::SPECIAL
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

MiniTest::Unit.autorun
