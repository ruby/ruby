require 'test/unit'

class TestFiber < Test::Unit::TestCase
  def test_normal
    f = Fiber.current
    assert_equal(:ok2,
      Fiber.new(:ok1){|e|
        assert_equal(:ok1, e)
        assert_equal(f, Fiber.prev)
        Fiber.pass :ok2
      }.pass)
  end

  def test_term
    assert_equal(:ok, Fiber.new{:ok}.pass)
    assert_equal([:a, :b, :c, :d, :e],
      Fiber.new{
        Fiber.new{
          Fiber.new{
            Fiber.new{
              [:a]
            }.pass + [:b]
          }.pass + [:c]
        }.pass + [:d]
      }.pass + [:e])
  end

  def test_many_fibers
    max = 10000
    assert_equal(max, max.times{
      Fiber.new{}
    })
    assert_equal(max,
      max.times{|i|
        Fiber.new{
        }.pass
      }
    )
  end

  def test_error
    assert_raise(ArgumentError){
      Fiber.new # Fiber without block
    }
    assert_raise(RuntimeError){
      f = Fiber.new{}
      Thread.new{f.pass}.join # Fiber passing across thread
    }
  end

  def test_loop
    ary = []
    f2 = nil
    f1 = Fiber.new{
      ary << f2.pass(:foo)
      :bar
    }
    f2 = Fiber.new{
      ary << f1.pass(:baz)
      :ok
    }
    assert_equal(:ok, f1.pass)
    assert_equal([:baz, :bar], ary)
  end
end

