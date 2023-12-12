class TimeoutAction
  def initialize(timeout)
    @timeout = timeout
    @queue = Queue.new
    @started = now
    @fail = false
    @error_message = "took longer than the configured timeout of #{@timeout}s"
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
                STDERR.puts "\nExample #{@error_message}:"
                STDERR.puts "#{@current_state.description}"
              else
                STDERR.puts "\nSome code outside an example #{@error_message}"
              end
              STDERR.flush

              show_backtraces
              if MSpec.subprocesses.empty?
                exit! 2
              else
                # Do not exit but signal the subprocess so we can get their output
                MSpec.subprocesses.each do |pid|
                  kill_wait_one_second :SIGTERM, pid
                  hard_kill :SIGKILL, pid
                end
                @fail = true
                @current_state = nil
                break # stop this thread, will fail in #after
              end
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

    if @fail
      STDERR.puts "\n\nThe last example #{@error_message}. See above for the subprocess stacktrace."
      exit! 2
    end
  end

  def finish
    @thread.kill
    @thread.join
  end

  private def hard_kill(signal, pid)
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
      # Process already terminated
    end
  end

  private def kill_wait_one_second(signal, pid)
    begin
      Process.kill signal, pid
      sleep 1
    rescue Errno::ESRCH
      # Process already terminated
    end
  end

  private def show_backtraces
    java_stacktraces = -> pid {
      if RUBY_ENGINE == 'truffleruby' || RUBY_ENGINE == 'jruby'
        STDERR.puts 'Java stacktraces:'
        kill_wait_one_second :SIGQUIT, pid
      end
    }

    if MSpec.subprocesses.empty?
      java_stacktraces.call Process.pid

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
    else
      MSpec.subprocesses.each do |pid|
        STDERR.puts "\nFor subprocess #{pid}"
        java_stacktraces.call pid

        if RUBY_ENGINE == 'truffleruby'
          STDERR.puts "\nRuby backtraces:"
          kill_wait_one_second :SIGALRM, pid
        else
          STDERR.puts "Don't know how to print backtraces of a subprocess on #{RUBY_ENGINE}"
        end
      end
    end
  end
end
