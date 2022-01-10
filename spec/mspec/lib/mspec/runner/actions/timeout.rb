class TimeoutAction
  def initialize(timeout)
    @timeout = timeout
    @queue = Queue.new
    @started = now
  end

  def register
    MSpec.register :start, self
    MSpec.register :before, self
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
              STDERR.puts "\n#{@current_state.description}"
              STDERR.puts "Example took longer than the configured timeout of #{@timeout}s"
              STDERR.flush

              if RUBY_ENGINE == 'truffleruby'
                STDERR.puts 'Java stacktraces:'
                Process.kill :SIGQUIT, Process.pid
                sleep 1

                if defined?(Truffle::Debug.show_backtraces)
                  STDERR.puts "\nRuby backtraces:"
                  Truffle::Debug.show_backtraces
                end
              end

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

  def finish
    @thread.kill
    @thread.join
  end
end
