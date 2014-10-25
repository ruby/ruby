require File.expand_path('../helper', __FILE__)

class TestRakeCpuCounter < Rake::TestCase

  def setup
    super

    @cpu_counter = Rake::CpuCounter.new
  end

  def test_count
    num = @cpu_counter.count
    skip 'cannot count CPU' if num == nil
    assert_kind_of Numeric, num
    assert_operator num, :>=, 1
  end

  def test_count_with_default_nil
    def @cpu_counter.count; nil; end
    assert_equal(8, @cpu_counter.count_with_default(8))
    assert_equal(4, @cpu_counter.count_with_default)
  end

  def test_count_with_default_raise
    def @cpu_counter.count; raise; end
    assert_equal(8, @cpu_counter.count_with_default(8))
    assert_equal(4, @cpu_counter.count_with_default)
  end

  class TestClassMethod < Rake::TestCase
    def setup
      super

      @klass = Class.new(Rake::CpuCounter)
    end

    def test_count
      @klass.class_eval do
        def count; 8; end
      end
      assert_equal(8, @klass.count)
    end

    def test_count_nil
      counted = false
      @klass.class_eval do
        define_method(:count) do
          counted = true
          nil
        end
      end
      assert_equal(4, @klass.count)
      assert_equal(true, counted)
    end

    def test_count_raise
      counted = false
      @klass.class_eval do
        define_method(:count) do
          counted = true
          raise
        end
      end
      assert_equal(4, @klass.count)
      assert_equal(true, counted)
    end
  end
end
