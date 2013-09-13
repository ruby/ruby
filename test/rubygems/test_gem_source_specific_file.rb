require 'rubygems/test_case'
require 'rubygems/source_specific_file'

class TestGemSourceSpecificFile < Gem::TestCase
  def setup
    super

    @a, @a_gem = util_gem "a", '1'
    @sf = Gem::Source::SpecificFile.new(@a_gem)
  end

  def test_spec
    assert_equal @a, @sf.spec
  end

  def test_load_specs
    assert_equal [@a.name_tuple], @sf.load_specs
  end

  def test_fetch_spec
    assert_equal @a, @sf.fetch_spec(@a.name_tuple)
  end

  def test_fetch_spec_fails_on_unknown_name
    assert_raises Gem::Exception do
      @sf.fetch_spec(nil)
    end
  end

  def test_download
    assert_equal @a_gem, @sf.download(@a)
  end
end
