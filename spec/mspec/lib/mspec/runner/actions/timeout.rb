class TimeoutAction
  def initialize(timeout)
    @timeout = timeout
    @queue = Queue.new
    @started = now
  end

  def register
    MSpec.register :start, self
    MSpec.register :before, self
    MSpec.register :after, self
    MSpec.register :finish, self
  end

  private def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  private def fetch_item
    @queue.pop(true)
  rescue ThreadError
    nil
  end

  def start
    @thread = Thread.new do
      loop do
        if action = fetch_item
          action.call
        else
          wakeup_at = @started + @timeout
          left = wakeup_at - now
          sleep left if left > 0
          Thread.pass # Let the main thread run

          if @queue.empty?
            elapsed = now - @started
            if elapsed > @timeout
              if @current_state
                STDERR.puts "\nExample took longer than the configured timeout of #{@timeout}s:"
                STDERR.puts "#{@current_state.description}"
              else
                STDERR.puts "\nSome code outside an example took longer than the configured timeout of #{@timeout}s"
              end
              STDERR.flush

              show_backtraces
              exit 2
            end
          end
        end
      end
    end
  end

  def before(state = nil)
    time = now
    @queue << -> do
      @current_state = state
      @started = time
    end
  end

  def after(state = nil)
    @queue << -> do
      @current_state = nil
    end
  end

  def finish
    @thread.kill
    @thread.join
  end

  private def show_backtraces
    if RUBY_ENGINE == 'truffleruby'
      STDERR.puts 'Java stacktraces:'
      Process.kill :SIGQUIT, Process.pid
      sleep 1
    end

    STDERR.puts "\nRuby backtraces:"
    if defined?(Truffle::Debug.show_backtraces)
      Truffle::Debug.show_backtraces
    else
      Thread.list.each do |thread|
        unless thread == Thread.current
          STDERR.puts thread.inspect, thread.backtrace, ''
        end
      end
    end
  end
end
