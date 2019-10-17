# frozen_string_literal: false
require 'test/unit'
require "-test-/string"
require "rbconfig/sizeof"

class Test_StringModifyExpand < Test::Unit::TestCase
  def test_modify_expand_memory_leak
    assert_no_memory_leak(["-r-test-/string"],
                          <<-PRE, <<-CMD, "rb_str_modify_expand()", limit: 2.5)
      s=Bug::String.new
    PRE
      size = $initial_size
      10.times{s.modify_expand!(size)}
      s.replace("")
    CMD
  end

  def test_integer_overflow
    return if RbConfig::SIZEOF['size_t'] > RbConfig::SIZEOF['long']
    bug12390 = '[ruby-core:75592] [Bug #12390]'
    s = Bug::String.new
    assert_raise(ArgumentError, bug12390) {
      s.modify_expand!(RbConfig::LIMITS["LONG_MAX"])
    }
  end
end
