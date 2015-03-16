require 'rubygems/source_list'
require 'rubygems/test_case'

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
    source = (sl << @uri)

    assert_kind_of Gem::Source, source

    assert_kind_of URI, source.uri
    assert_equal source.uri.to_s, @uri

    assert_equal [source], sl.sources
  end

  def test_clear
    sl = Gem::SourceList.new

    sl << 'http://source.example'

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

    sl << 'http://source.example'

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
    assert @sl.include?(URI.parse(@uri)), "uri comparison not working"
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

end
