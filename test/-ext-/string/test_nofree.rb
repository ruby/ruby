require 'test/unit'

class Test_StringNoFree < Test::Unit::TestCase
  def test_no_memory_leak
    bug10942 = '[ruby-core:68436] [Bug #10942] no leak on nofree string'
    assert_no_memory_leak(%w(-r-test-/string/string), '',
                          '1000000.times {Bug::String.nofree << "a" * 100}',
                          bug10942, rss: true, limit: 2.0)
  end
end
