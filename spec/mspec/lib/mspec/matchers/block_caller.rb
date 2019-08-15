class BlockingMatcher
  def matches?(block)
    t = Thread.new do
      block.call
    end

    loop do
      case t.status
      when "sleep"    # blocked
        t.kill
        t.join
        return true
      when false      # terminated normally, so never blocked
        t.join
        return false
      when nil        # terminated exceptionally
        t.value
      else
        Thread.pass
      end
    end
  end

  def failure_message
    ['Expected the given Proc', 'to block the caller']
  end

  def negative_failure_message
    ['Expected the given Proc', 'to not block the caller']
  end
end

module MSpecMatchers
  private def block_caller
    BlockingMatcher.new
  end
end
