# frozen_string_literal: true

require "test/unit"
require "envutil"

class TestEnvUtil < Test::Unit::TestCase
  def test_rubybin_points_to_a_ruby_executable
    assert(File.executable?(EnvUtil.rubybin))
  end

  def test_apply_timeout_scale
    original_scale = EnvUtil.timeout_scale
    EnvUtil.timeout_scale = 2.5

    assert_equal(5.0, EnvUtil.apply_timeout_scale(2))
  ensure
    EnvUtil.timeout_scale = original_scale
  end

  def test_invoke_ruby_captures_output_and_status
    stdout, stderr, status = EnvUtil.invoke_ruby(
      ["-e", "STDOUT.print('out'); STDERR.print('err')"],
      "", true, true
    )

    assert_equal("out", stdout)
    assert_equal("err", stderr)
    assert_predicate(status, :success?)
  end
end
