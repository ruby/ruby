# -*- ruby-indent-level: 4 -*-
require 'thread'
require 'test/unit'

class TC_Thread < Test::Unit::TestCase
    def setup
	Thread.abort_on_exception = true
    end
    def teardown
	Thread.abort_on_exception = false
    end
    def test_condvar
	mutex = Mutex.new
	condvar = ConditionVariable.new
	result = []
	mutex.synchronize do
	    t = Thread.new do
		mutex.synchronize do
		    result << 1
		    condvar.signal
		end
	    end
	
	    result << 0
	    condvar.wait(mutex)
	    result << 2
	    t.join
	end
	assert_equal([0, 1, 2], result)
    end

    def test_condvar_wait_not_owner
	mutex = Mutex.new
	condvar = ConditionVariable.new

	assert_raises(ThreadError) { condvar.wait(mutex) }
    end

    def test_condvar_wait_exception_handling
	# Calling wait in the only thread running should raise a ThreadError of
	# 'stopping only thread'
	mutex = Mutex.new
	condvar = ConditionVariable.new

	Thread.abort_on_exception = false

	locked = false
	thread = Thread.new do
	    mutex.synchronize do
		begin
		    condvar.wait(mutex)
		rescue Exception
		    locked = mutex.locked?
		    raise
		end
	    end
	end

	while !thread.stop?
	    sleep(0.1)
	end

	thread.raise Interrupt, "interrupt a dead condition variable"
	assert_raises(Interrupt) { thread.value }
	assert(locked)
    end

    def test_local_barrier
        dir = File.dirname(__FILE__)
        lbtest = File.join(dir, "lbtest.rb")
        $:.unshift File.join(File.dirname(dir), 'ruby')
        require 'envutil'
        $:.shift
        10.times {
            result = `#{EnvUtil.rubybin} #{lbtest}`
            assert(!$?.coredump?, '[ruby-dev:30653]')
            assert_equal("exit.", result[/.*\Z/], '[ruby-dev:30653]')
        }
    end

    def test_queue_rescue
        require "timeout"
        queue = Queue.new
        assert_raises(Timeout::Error) {Timeout.timeout(0.001) {queue.pop}}
        queue.push(1)
        assert_nothing_raised("[ruby-dev:37545]") {assert_equal(1, queue.pop)}
        assert(queue.empty?)
    end
end

