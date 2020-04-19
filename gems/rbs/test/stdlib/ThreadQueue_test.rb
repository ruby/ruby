require_relative "test_helper"

class ThreadQueueTest < StdlibTest
  target Thread::Queue
  using hook.refinement

  def test_lshift
    q = Thread::Queue.new
    q << :a
  end

  def test_clear
    q = Thread::Queue.new
    q.clear
  end

  def test_close
    q = Thread::Queue.new
    q.close
  end

  def test_closed?
    q = Thread::Queue.new
    q.closed?
    q.close
    q.closed?
  end

  def test_deq
    q = Thread::Queue.new
    3.times { q << :a }

    q.deq
    q.deq(true)
    q.deq(false)
  end

  def test_empty?
    q = Thread::Queue.new
    q.empty?
    q << :a
    q.empty?
  end

  def test_enq
    q = Thread::Queue.new
    q.enq(:a)
  end

  def test_length
    q = Thread::Queue.new
    q.length
  end

  def test_num_waiting
    q = Thread::Queue.new
    q.num_waiting
  end

  def test_pop
    q = Thread::Queue.new
    3.times { q << :a }
    q.pop
    q.pop(true)
    q.pop(false)
  end

  def test_push
    q = Thread::Queue.new
    q.push(:a)
  end

  def test_shift
    q = Thread::Queue.new
    3.times { q << :a }
    q.shift
    q.shift(true)
    q.shift(false)
  end

  def test_size
    q = Thread::Queue.new
    q.size
  end
end
