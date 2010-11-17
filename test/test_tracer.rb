require 'test/unit'
require_relative 'ruby/envutil'

class TestTracer < Test::Unit::TestCase
  include EnvUtil

  def test_work_with_e
    assert_in_out_err(%w[-rtracer -e 1]) do |(*lines),|
      case lines.size
      when 2
        assert_match %r[#0:<internal:lib/rubygems/custom_require>:\d+:Kernel:<: -], lines[0]
      when 1
        # do nothing
      else
        flunk 'unexpected output from `ruby -rtracer -e 1`'
      end
      assert_equal "#0:-e:1::-: 1", lines[1]
    end
  end
end
