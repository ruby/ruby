require File.expand_path('../helper', __FILE__)
require 'rake/thread_pool'
require 'test/unit/assertions'

class TestRakeTestThreadPool < Rake::TestCase
  include Rake

  def test_pool_executes_in_current_thread_for_zero_threads
    pool = ThreadPool.new(0)
    f = pool.future{Thread.current}
    pool.join
    assert_equal Thread.current, f.value
  end

  def test_pool_executes_in_other_thread_for_pool_of_size_one
    pool = ThreadPool.new(1)
    f = pool.future{Thread.current}
    pool.join
    refute_equal Thread.current, f.value
  end

  def test_pool_executes_in_two_other_threads_for_pool_of_size_two
    pool = ThreadPool.new(2)
    threads = 2.times.collect{ pool.future{ sleep 0.1; Thread.current } }.each{|f|f.value}

    refute_equal threads[0], threads[1]
    refute_equal Thread.current, threads[0]
    refute_equal Thread.current, threads[1]
  end

  def test_pool_creates_the_correct_number_of_threads
    pool = ThreadPool.new(2)
    threads = Set.new
    t_mutex = Mutex.new
    10.times.each do
      pool.future do
        sleep 0.02
        t_mutex.synchronize{ threads << Thread.current }
      end
    end
    pool.join
    assert_equal 2, threads.count
  end

  def test_pool_future_captures_arguments
    pool = ThreadPool.new(2)
    a = 'a'
    b = 'b'
    c = 5 # 5 throws an execption with 5.dup. It should be ignored
    pool.future(a,c){ |a_var,ignore| a_var.capitalize!; b.capitalize! }
    pool.join
    assert_equal 'a', a
    assert_equal 'b'.capitalize, b
  end

  def test_pool_join_empties_queue
    pool = ThreadPool.new(2)
    repeat = 25
    repeat.times {
      pool.future do
        repeat.times {
          pool.future do
            repeat.times {
              pool.future do end
            }
          end
        }
      end
    }

    pool.join
    assert_equal true, pool.__send__(:__queue__).empty?, "queue should be empty"
  end

  # test that throwing an exception way down in the blocks propagates
  # to the top
  def test_exceptions
    pool = ThreadPool.new(10)

    deep_exception_block = lambda do |count|
      next raise Exception.new if ( count < 1 )
      pool.future(count-1, &deep_exception_block).value
    end

    assert_raises(Exception) do
      pool.future(2, &deep_exception_block).value
    end

  end

  def test_pool_prevents_deadlock
    pool = ThreadPool.new(5)

    common_dependency_a = pool.future { sleep 0.2 }
    futures_a = 10.times.collect { pool.future{ common_dependency_a.value; sleep(rand() * 0.01) } }

    common_dependency_b = pool.future { futures_a.each { |f| f.value } }
    futures_b = 10.times.collect { pool.future{ common_dependency_b.value; sleep(rand() * 0.01) } }

    futures_b.each{|f|f.value}
    pool.join
  end

  def test_pool_reports_correct_results
    pool = ThreadPool.new(7)

    a = 18
    b = 5
    c = 3

    result = a.times.collect do
      pool.future do
        b.times.collect do
          pool.future { sleep rand * 0.001; c }
        end.inject(0) { |m,f| m+f.value }
      end
    end.inject(0) { |m,f| m+f.value }

    assert_equal( (a*b*c), result )
    pool.join
  end

end
