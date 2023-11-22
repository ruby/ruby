require 'test/unit'

module TestSlowTimeout
  def test_slow
    sleep (ENV['sec'] || 3).to_i if on_parallel_worker?
  end
end
