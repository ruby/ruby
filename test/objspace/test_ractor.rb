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

  def test_trace_object_allocations_with_ractor_tracepoint
    # Test that ObjectSpace.trace_object_allocations works globally across all Ractors
    assert_ractor(<<~'RUBY', require: 'objspace')
      ObjectSpace.trace_object_allocations do
        obj1 = Object.new; line1 = __LINE__
        assert_equal __FILE__, ObjectSpace.allocation_sourcefile(obj1)
        assert_equal line1, ObjectSpace.allocation_sourceline(obj1)

        r = Ractor.new {
          obj = Object.new; line = __LINE__
          [line, obj]
        }

        obj2 = Object.new; line2 = __LINE__
        assert_equal __FILE__, ObjectSpace.allocation_sourcefile(obj2)
        assert_equal line2, ObjectSpace.allocation_sourceline(obj2)

        expected_line, ractor_obj = r.value
        assert_equal __FILE__, ObjectSpace.allocation_sourcefile(ractor_obj)
        assert_equal expected_line, ObjectSpace.allocation_sourceline(ractor_obj)

        obj3 = Object.new; line3 = __LINE__
        assert_equal __FILE__, ObjectSpace.allocation_sourcefile(obj3)
        assert_equal line3, ObjectSpace.allocation_sourceline(obj3)
      end
    RUBY
  end
end
