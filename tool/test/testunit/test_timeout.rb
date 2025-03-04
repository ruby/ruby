# frozen_string_literal: false
require 'test/unit'
require 'envutil'

class TestTiemout < Test::Unit::TestCase
  def test_timeout
    cmd = [*@__runner_options__[:ruby], "#{File.dirname(__FILE__)}/test4test_timeout.rb"]
    result = IO.popen(cmd, err: [:child, :out], &:read)
    assert_not_match(/^T{10}$/, result)
  end

  def test_timeout_scale
    scale = ENV['RUBY_TEST_TIMEOUT_SCALE']&.to_f
    sec = 5

    if scale
      assert_equal sec * scale, EnvUtil.apply_timeout_scale(sec)
    else
      assert_equal sec, EnvUtil.apply_timeout_scale(sec)
    end

    STDERR.puts [scale, sec, EnvUtil.apply_timeout_scale(sec)].inspect
  end
end
