# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'

class TestThreadTVar < Test::Unit::TestCase
  def test_tvar_new
    tv = Thread::TVar.new(0)
    assert_equal Thread::TVar, tv.class

    assert_raise(ArgumentError, /only shareable object are allowed/) do
      Thread::TVar.new([1, 2, 3])
    end
  end

  # without atomically

  def test_tvar_value_without_atomically
    tv = Thread::TVar.new(42)
    assert_equal 42, tv.value
  end

  def test_tvar_value_increment_without_atomically
    tv = Thread::TVar.new(42)

    # default +1
    assert_equal 43, tv.increment
    assert_equal 43, tv.value

    assert_equal 40, tv.increment(-3)
    assert_equal 40, tv.value
  end

  def test_tvar_value_set_raise_without_atomically
    tv = Thread::TVar.new(42)
    assert_raise(Thread::TransactionError){
      tv.value = 43
    }
  end

  # with atomically

  def test_tvar_value_set
    tv = Thread::TVar.new(42)
    Thread.atomically do 
      assert_equal 43, (tv.value += 1)
    end
    assert_equal 43, tv.value

    q1 = Queue.new
    q2 = Queue.new

    t1 = Thread.new do
      retried = false
      Thread.atomically do
        q1.pop unless retried
        # (2)
        if !retried
          assert_equal 43, v = tv.value
        else
          # after retried
          assert_equal 44, v = tv.value
        end
        q2 << true
        q1.pop unless retried

        retried = true
        tv.value = v + 1 #=> abort because tv is already rewitten
      end
      assert_equal 45, tv.value
      assert_equal true, retried
    end

    t2 = Thread.new do
      # (1)
      q1 << true
      q2.pop
      # (3)
      tv.increment
      q1 << true
    end

    t1.join
  end

  def test_tvar_value_get
    # tv1 and tv2 should be same values
    tv1 = Thread::TVar.new(42)
    tv2 = Thread::TVar.new(42)

    q1 = Queue.new
    q2 = Queue.new

    reader = Thread.new{
      retried = false
      Thread.atomically do
        # (2)
        q1.pop unless retried
        a = tv1.value
        q2 << true
        q1.pop unless retried
        # (4)
        retried = true
        b = tv2.value #=> retry because tv2 is written after tv1 read
        assert_equal true, a == b
        assert_equal true, retried
      end
    }

    Thread.new{
      Thread.atomically do
        # (1)
        q1 << true
        q2.pop
        # (3)
        tv1.increment
        tv2.increment
        q1 << true
      end
    }

    reader.join
  end
  
  def test_tvar_value_increment
    tv = Thread::TVar.new(42)

    Thread.atomically do
      assert_equal 43, tv.increment
      assert_equal 43, tv.value
    end
    assert_equal 43, tv.value

    Thread.atomically do
      assert_equal 40, tv.increment(-3)
      assert_equal 40, tv.value
    end
    assert_equal 40, tv.value
  end

  def test_tvar_nested_atomically
    tv = Thread::TVar.new(42)

    # nested atomically calls are just ignored
    Thread.atomically do
      Thread.atomically do
        Thread.atomically do
          tv.value += 1
        end
        tv.value += 1
      end
      tv.value += 1
    end

    assert_equal 45, tv.value
  end
end


