require 'test/unit'

module TestSlowTimeout
  def test_slow
    sleep_for = EnvUtil.apply_timeout_scale((ENV['sec'] || 3).to_i)
    sleep sleep_for if on_parallel_worker?
  end
end
