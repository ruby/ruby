require "test/unit"
require "benchmark"

class TestBenchmark < Test::Unit::TestCase
  def test_add!
    assert_nothing_raised("[ruby-dev:40906]") do
      Benchmark::Tms.new.add! {}
    end
  end
end
