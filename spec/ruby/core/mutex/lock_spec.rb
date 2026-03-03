require_relative '../../spec_helper'

describe "Mutex#lock" do
  it "returns self" do
    m = Mutex.new
    m.lock.should == m
    m.unlock
  end

  it "blocks the caller if already locked" do
    m = Mutex.new
    m.lock
    -> { m.lock }.should block_caller
  end

  it "does not block the caller if not locked" do
    m = Mutex.new
    -> { m.lock }.should_not block_caller
  end

  # Unable to find a specific ticket but behavior change may be
  # related to this ML thread.
  it "raises a deadlock ThreadError when used recursively" do
    m = Mutex.new
    m.lock
    -> {
      m.lock
    }.should raise_error(ThreadError, /deadlock/)
  end

  it "raises a deadlock ThreadError when multiple fibers from the same thread try to lock" do
    m = Mutex.new

    m.lock
    f0 = Fiber.new do
      m.lock
    end
    -> { f0.resume }.should raise_error(ThreadError, /deadlock/)

    m.unlock
    f1 = Fiber.new do
      m.lock
      Fiber.yield
    end
    f2 = Fiber.new do
      m.lock
    end
    f1.resume
    -> { f2.resume }.should raise_error(ThreadError, /deadlock/)
  end

  it "does not raise deadlock if a fiber's attempt to lock was interrupted" do
    lock = Mutex.new
    main = Thread.current

    t2 = nil
    t1 = Thread.new do
      loop do
        # interrupt fiber below looping on synchronize
        sleep 0.01
        t2.raise if t2
      end
    end

    # loop ten times to try to handle the interrupt during synchronize
    t2 = Thread.new do
      10.times do
        Fiber.new do
          begin
            loop { lock.synchronize {} }
          rescue RuntimeError
          end
        end.resume

        Fiber.new do
          -> do
            lock.synchronize {}
          end.should_not raise_error(ThreadError)
        end.resume
      rescue RuntimeError
        retry
      end
    end
    t2.join
  ensure
    t1.kill rescue nil
    t2.kill rescue nil

    t1.join
    t2.join
  end
end
