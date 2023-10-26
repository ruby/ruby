# frozen_string_literal: false
require 'test/unit'

class TestTiemout < Test::Unit::TestCase
  def test_timeout
    cmd = [*@__runner_options__[:ruby], "#{File.dirname(__FILE__)}/test4test_timeout.rb"]
    result = IO.popen(cmd, err: [:child, :out], &:read)
    assert_not_match(/^T{10}$/, result)
  end
end
