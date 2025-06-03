require "test/unit"

class TestObjSpaceRactor < Test::Unit::TestCase
  def test_tracing_does_not_crash
    assert_ractor(<<~RUBY, require: 'objspace')
      ObjectSpace.trace_object_allocations do
        r = Ractor.new do
          _obj = 'a' * 1024
        end

        r.join
      end
    RUBY
  end

  def test_undefine_finalizer
    assert_ractor(<<~'RUBY', require: 'objspace')
      def fin
        ->(id) { }
      end
      ractors = 5.times.map do
        Ractor.new do
          10_000.times do
            o = Object.new
            ObjectSpace.define_finalizer(o, fin)
            ObjectSpace.undefine_finalizer(o)
          end
        end
      end

      ractors.each(&:join)
    RUBY
  end

  def test_copy_finalizer
    assert_ractor(<<~'RUBY', require: 'objspace')
      def fin
        ->(id) { }
      end
      OBJ = Object.new
      ObjectSpace.define_finalizer(OBJ, fin)
      OBJ.freeze

      ractors = 5.times.map do
        Ractor.new do
          10_000.times do
            OBJ.clone
          end
        end
      end

      ractors.each(&:join)
    RUBY
  end
end
