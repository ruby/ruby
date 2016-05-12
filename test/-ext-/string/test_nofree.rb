# frozen_string_literal: false
require 'test/unit'

class Test_StringNoFree < Test::Unit::TestCase
  def test_no_memory_leak
    bug10942 = '[ruby-core:68436] [Bug #10942] no leak on nofree string'
    code = '.times {Bug::String.nofree << "a" * 100}'
    assert_no_memory_leak(%w(-r-test-/string),
                          "100_000#{code}",
                          "1_000_000#{code}",
                          bug10942, rss: true)
  end
end
