require "test/unit"

class TestObjSpaceRactor < Test::Unit::TestCase
  def test_tracing_does_not_crash
    assert_ractor(<<~RUBY, require: 'objspace')
      ObjectSpace.trace_object_allocations do
        r = Ractor.new do
          obj = 'a' * 1024
          Ractor.yield obj
        end

        r.take
        r.take
      end
    RUBY
  end
end
