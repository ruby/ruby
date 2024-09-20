assert_equal '0', %q{
  begin
    GC.stress = true
    pid = fork {}
    Process.wait pid
    $?.to_i
  rescue NotImplementedError
    0
  end
}, '[ruby-dev:32404]'

assert_finish 10, %q{
  begin
    children = (1..10).map{
      Thread.start{fork{}}.value
    }
    while !children.empty? and pid = Process.wait
      children.delete(pid)
    end
  rescue NotImplementedError
  end
}, '[ruby-core:22158]'

# temporarily stop this test to enable explicit failure when
# timer thread couldn't be created (r61706 and r61717).
assert_normal_exit(<<'End', '[ruby-dev:37934]') if false
  main = Thread.current
  Thread.new { sleep 0.01 until main.stop?; Thread.kill main }
  Process.setrlimit(:NPROC, 1) if defined?(Process::RLIMIT_NPROC)
  fork {}
End

assert_equal 'ok', %q{
  begin
    r, w = IO.pipe
    if pid1 = fork
      w.close
      r.read(1)
      Process.kill("USR1", pid1)
      _, s = Process.wait2(pid1)
      s.success? ? :ok : :ng
    else
      r.close
      if pid2 = fork
        trap("USR1") { Time.now.to_s; Process.kill("USR2", pid2) }
        w.close
        Process.wait2(pid2)
      else
        w.close
        sleep 0.2
      end
      exit true
    end
  rescue NotImplementedError
    :ok
  end
}, '[ruby-core:28924]'

assert_equal '[1, 2]', %q{
  a = []
  main = Thread.current
  trap(:INT) { a.push(1).size == 2 and main.wakeup }
  trap(:TERM) { a.push(2).size == 2 and main.wakeup }
  pid = $$
  begin
    pid = fork do
      Process.kill(:INT, pid)
      Process.kill(:TERM, pid)
    end
    Process.wait(pid)
    100.times {break if a.size > 1; sleep 0.001}
    a.sort
  rescue NotImplementedError
    [1, 2]
  end
}, '[ruby-dev:44005] [Ruby 1.9 - Bug #4950]'

assert_equal 'ok', %q{
  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  Thread.new do
    loop { sleep 0.0001 }
  end

  10.times do
    pid = fork{ exit!(0) }
    deadline = now + 1
    until Process.waitpid(pid, Process::WNOHANG)
      if now > deadline
        Process.kill(:KILL, pid)
        raise "failed"
      end
      sleep 0.001
    end
  rescue NotImplementedError
  end
  :ok
}, '[Bug #20670]'

