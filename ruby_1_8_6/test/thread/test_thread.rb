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
end

