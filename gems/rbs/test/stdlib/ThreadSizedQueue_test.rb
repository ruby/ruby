require_relative "test_helper"

class ThreadSizedQueueTest < StdlibTest
  target Thread::SizedQueue
  using hook.refinement

  def test_lshift
    q = Thread::SizedQueue.new(3)
    q << :a
    q.<<(:a, true)
    q.<<(:a, false)
  end

  def test_enq
    q = Thread::SizedQueue.new(3)
    q.enq(:a)
    q.enq(:a, true)
    q.enq(:a, false)
  end

  def test_initialize
    Thread::SizedQueue.new(1)
  end

  def test_max
    q = Thread::SizedQueue.new(1)
    q.max
  end

  def test_max=
    q = Thread::SizedQueue.new(1)
    q.max = 1
  end

  def test_push
    q = Thread::SizedQueue.new(3)
    q.push(:a)
    q.push(:a, true)
    q.push(:a, false)
  end
end
