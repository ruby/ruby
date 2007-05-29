require 'test/unit'

class TestContinuation < Test::Unit::TestCase
  def test_create
    assert_equal(:ok, callcc{:ok})
    assert_equal(:ok, callcc{|c| c.call :ok})
  end

  def test_call
    assert_equal(:ok, callcc{|c| c.call :ok})

    ary = []
    ary << callcc{|c|
      @cont = c
      :a
    }
    @cont.call :b if ary.length < 3
    assert_equal([:a, :b, :b], ary)
  end

  def test_error
    cont = callcc{|c| c}
    assert_raise(RuntimeError){
      Thread.new{cont.call}.join
    }
    assert_raise(LocalJumpError){
      callcc
    }
  end
end

