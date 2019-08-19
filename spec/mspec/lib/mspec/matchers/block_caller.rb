class BlockingMatcher
  def matches?(block)
    started = false
    blocking = true

    thread = Thread.new do
      started = true
      block.call

      blocking = false
    end

    Thread.pass while !started

    # Wait until the Thread status is "sleep" (then it's blocking)
    # or nil (the Thread finished execution, it did not block)
    while status = thread.status and status != "sleep"
      Thread.pass
    end
    thread.kill
    thread.join

    blocking
  end

  def failure_message
    ['Expected the given Proc', 'to block the caller']
  end

  def negative_failure_message
    ['Expected the given Proc', 'to not block the caller']
  end
end

module MSpecMatchers
  private def block_caller(timeout = 0.1)
    BlockingMatcher.new
  end
end
