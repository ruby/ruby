# frozen_string_literal: true

require_relative "helper"
require "rubygems/source_list"

class TestGemSourceList < Gem::TestCase
  def setup
    super

    @uri = "http://example"
    @source = Gem::Source.new(@uri)

    @sl = Gem::SourceList.new
    @sl << @source
  end

  def test_self_from
    sl = Gem::SourceList.from [@uri]

    assert_equal [Gem::Source.new(@uri)], sl.sources
  end

  def test_Enumerable
    assert_includes Gem::SourceList.ancestors, Enumerable
  end

  def test_append
    sl = Gem::SourceList.new
    sl << @uri
    sl << @uri

    assert_equal sl.to_a.size, 1

    sl.clear
    source = (sl << @uri)

    assert_kind_of Gem::Source, source

    assert_kind_of Gem::URI, source.uri
    assert_equal source.uri.to_s, @uri

    assert_equal [source], sl.sources
  end

  def test_clear
    sl = Gem::SourceList.new

    sl << "http://source.example"

    sl.clear

    assert_empty sl
  end

  def test_replace
    sl = Gem::SourceList.new
    sl.replace [@uri]

    assert_equal [@source], sl.sources
  end

  def test_each
    @sl.each do |x|
      assert_equal @uri, x
    end
  end

  def test_each_source
    @sl.each_source do |x|
      assert_equal @source, x
    end
  end

  def test_empty?
    sl = Gem::SourceList.new

    assert_empty sl

    sl << "http://source.example"

    refute_empty sl
  end

  def test_equal_to_another_list
    sl2 = Gem::SourceList.new
    sl2 << Gem::Source.new(@uri)

    assert @sl == sl2, "lists not equal"
  end

  def test_equal_to_array
    assert @sl == [@uri], "lists not equal"
  end

  def test_to_a
    assert_equal @sl.to_a, [@uri]
  end

  def test_include_eh
    assert @sl.include?(@uri), "string comparison not working"
    assert @sl.include?(Gem::URI.parse(@uri)), "uri comparison not working"
  end

  def test_include_matches_a_source
    assert @sl.include?(@source), "source comparison not working"
    assert @sl.include?(Gem::Source.new(@uri)), "source comparison not working"
  end

  def test_delete
    @sl.delete @uri
    assert_equal @sl.sources, []
  end

  def test_delete_a_source
    @sl.delete Gem::Source.new(@uri)
    assert_equal @sl.sources, []
  end

  def test_prepend_new_source
    uri2 = "http://example2"
    source2 = Gem::Source.new(uri2)

    result = @sl.prepend(uri2)

    assert_kind_of Gem::Source, result
    assert_kind_of Gem::URI, result.uri
    assert_equal uri2, result.uri.to_s
    assert_equal [source2, @source], @sl.sources
  end

  def test_prepend_existing_source
    uri2 = "http://example2"
    source2 = Gem::Source.new(uri2)
    @sl << uri2

    assert_equal [@source, source2], @sl.sources

    result = @sl.prepend(uri2)

    assert_kind_of Gem::Source, result
    assert_kind_of Gem::URI, result.uri
    assert_equal uri2, result.uri.to_s
    assert_equal [source2, @source], @sl.sources
  end

  def test_prepend_alias_behaves_like_unshift
    sl = Gem::SourceList.new

    uri1 = "http://one"
    uri2 = "http://two"

    source1 = sl << uri1
    source2 = sl << uri2

    # move existing to front
    result = sl.prepend(uri2)

    assert_kind_of Gem::Source, result
    assert_equal [source2, source1], sl.sources

    # and again with the other
    result = sl.prepend(uri1)
    assert_equal [source1, source2], sl.sources
  end

  def test_append_method_new_source
    sl = Gem::SourceList.new

    uri1 = "http://example1"

    result = sl.append(uri1)

    assert_kind_of Gem::Source, result
    assert_kind_of Gem::URI, result.uri
    assert_equal uri1, result.uri.to_s
    assert_equal [result], sl.sources
  end

  def test_append_method_existing_moves_to_end
    sl = Gem::SourceList.new

    uri1 = "http://example1"
    uri2 = "http://example2"

    s1 = sl << uri1
    s2 = sl << uri2

    # list is [s1, s2]; appending s1 should move it to end => [s2, s1]
    result = sl.append(uri1)

    assert_equal s1, result
    assert_equal [s2, s1], sl.sources
  end

  def test_prepend_with_gem_source_object
    sl = Gem::SourceList.new

    uri1 = "http://example1"
    uri2 = "http://example2"
    source1 = Gem::Source.new(uri1)
    source2 = Gem::Source.new(uri2)

    # Add first source
    sl << source1

    # Prepend with Gem::Source object
    result = sl.prepend(source2)

    assert_equal source2, result
    assert_equal [source2, source1], sl.sources

    # Prepend existing source - should move to front
    result = sl.prepend(source1)

    assert_equal source1, result
    assert_equal [source1, source2], sl.sources
  end

  def test_append_with_gem_source_object
    sl = Gem::SourceList.new

    uri1 = "http://example1"
    uri2 = "http://example2"
    source1 = Gem::Source.new(uri1)
    source2 = Gem::Source.new(uri2)

    # Add first source
    sl << source1

    # Append with Gem::Source object
    result = sl.append(source2)

    assert_equal source2, result
    assert_equal [source1, source2], sl.sources

    # Append existing source - should move to end
    result = sl.append(source1)

    assert_equal source1, result
    assert_equal [source2, source1], sl.sources
  end
end
