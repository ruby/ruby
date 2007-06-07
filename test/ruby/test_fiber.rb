require 'test/unit'

class TestFiber < Test::Unit::TestCase
  def test_normal
    f = Fiber.current
    assert_equal(:ok2,
      Fiber.new{|e|
        assert_equal(:ok1, e)
        assert_equal(f, Fiber.prev)
        Fiber.yield :ok2
      }.yield(:ok1)
    )
    assert_equal([:a, :b], Fiber.new{|a, b| [a, b]}.yield(:a, :b))
  end

  def test_term
    assert_equal(:ok, Fiber.new{:ok}.yield)
    assert_equal([:a, :b, :c, :d, :e],
      Fiber.new{
        Fiber.new{
          Fiber.new{
            Fiber.new{
              [:a]
            }.yield + [:b]
          }.yield + [:c]
        }.yield + [:d]
      }.yield + [:e])
  end

  def test_many_fibers
    max = 10000
    assert_equal(max, max.times{
      Fiber.new{}
    })
    assert_equal(max,
      max.times{|i|
        Fiber.new{
        }.yield
      }
    )
  end

  def test_many_fibers_with_threads
    max = 1000
    @cnt = 0
    (1..100).map{|ti|
      Thread.new{
        max.times{|i|
          Fiber.new{
            @cnt += 1
          }.yield
        }
      }
    }.each{|t|
      t.join
    }
    assert_equal(:ok, :ok)
  end

  def test_error
    assert_raise(ArgumentError){
      Fiber.new # Fiber without block
    }
    assert_raise(FiberError){
      f = Fiber.new{}
      Thread.new{f.yield}.join # Fiber yielding across thread
    }
    assert_raise(FiberError){
      f = Fiber.new{}
      f.yield
      f.yield
    }
  end

  def test_loop
    ary = []
    f2 = nil
    f1 = Fiber.new{
      ary << f2.yield(:foo)
      :bar
    }
    f2 = Fiber.new{
      ary << f1.yield(:baz)
      :ok
    }
    assert_equal(:ok, f1.yield)
    assert_equal([:baz, :bar], ary)
  end

  def test_return
    assert_raise(LocalJumpError){
      Fiber.new do
        return
      end.yield
    }
  end

  def test_throw
    assert_raise(RuntimeError){
      Fiber.new do
        throw :a
      end.yield
    }
  end

  def test_with_callcc
    c = nil
    f1 = f2 = nil
    f1 = Fiber.new do
      callcc do |c2|
        c = c2
        f2.yield
      end
      :ok
    end
    f2 = Fiber.new do
      c.call
    end
    assert_equal(:ok, f1.yield)

    assert_equal(:ok,
      callcc {|c|
        Fiber.new {
          c.call :ok
        }.yield
      }
    )
  end
end

