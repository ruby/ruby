show_limit %q{
  threads = []
  begin
    threads << Thread.new{sleep}

    raise Exception, "skipping" if threads.count >= 10_000
  rescue Exception => error
    puts "Thread count: #{threads.count} (#{error})"
    break
  end while true
} if false # disable to pass CI

assert_equal %q{ok}, %q{
  Thread.new{
  }.join
  :ok
}
assert_equal %q{ok}, %q{
  Thread.new{
    :ok
  }.value
}
assert_equal %q{ok}, %q{
begin
  v = 0
  (1..200).map{|i|
    Thread.new{
      i
    }
  }.each{|t|
    v += t.value
  }
  v == 20100 ? :ok : v
rescue ThreadError => e
  :ok if /can't create Thread/ =~ e.message
end
}
assert_equal %q{ok}, %q{
begin
  :ok if 5000 == 5000.times{|e|
    (1..2).map{
      Thread.new{
      }
    }.each{|e|
      e.join()
    }
  }
rescue ThreadError => e
  /can't create Thread/ =~ e.message ? :ok : e.message
end
}
assert_equal %q{ok}, %q{
begin
  :ok if 5000 == 5000.times{|e|
    (1..2).map{
      Thread.new{
      }
    }.each{|e|
      e.join(1000000000)
    }
  }
rescue ThreadError => e
  /can't create Thread/ =~ e.message ? :ok : e.message
end
}
assert_equal %q{ok}, %q{
begin
  :ok if 5000 == 5000.times{
    t = Thread.new{}
    while t.alive?
      Thread.pass
    end
  }
rescue NoMemoryError
  :ok
end
}
assert_equal %q{100}, %q{
  100.times{
    Thread.new{loop{Thread.pass}}
  }
}
assert_equal %q{ok}, %q{
  Thread.new{
    :ok
  }.join.value
}
assert_equal %q{ok}, %q{
  begin
    Thread.new{
      raise "ok"
    }.join
  rescue => e
    e
  end
}
assert_equal %q{ok}, %q{
  ans = nil
  t = Thread.new{
    begin
      sleep 0.5
    ensure
      ans = :ok
    end
  }
  Thread.pass until t.stop?
  t.kill
  t.join
  ans
}
assert_equal %q{ok}, %q{
  t = Thread.new{
    sleep
  }
  sleep 0.1
  t.raise
  begin
    t.join
    :ng
  rescue
    :ok
  end
}
assert_equal %q{ok}, %q{
  t = Thread.new{
    loop{}
  }
  Thread.pass
  t.raise
  begin
    t.join
    :ng
  rescue
    :ok
  end
}
assert_equal %q{ok}, %q{
  t = Thread.new{
  }
  Thread.pass
  t.join
  t.raise # raise to exited thread
  begin
    t.join
    :ok
  rescue
    :ng
  end
}
assert_equal %q{run}, %q{
  t = Thread.new{
    loop{}
  }
  st = t.status
  t.kill
  st
}
assert_equal %q{sleep}, %q{
  t = Thread.new{
    sleep
  }
  sleep 0.1
  st = t.status
  t.kill
  st
}
assert_equal %q{false}, %q{
  t = Thread.new{
  }
  t.kill
  sleep 0.1
  t.status
}
assert_equal %q{[ThreadGroup, true]}, %q{
  ptg = Thread.current.group
  Thread.new{
    ctg = Thread.current.group
    [ctg.class, ctg == ptg]
  }.value
}
assert_equal %q{[1, 1]}, %q{
  thg = ThreadGroup.new

  t = Thread.new{
    thg.add Thread.current
    sleep
  }
  sleep 0.1
  [thg.list.size, ThreadGroup::Default.list.size]
}
assert_equal %q{true}, %q{
  thg = ThreadGroup.new

  t = Thread.new{sleep 5}
  thg.add t
  thg.list.include?(t)
}
assert_equal %q{[true, nil, true]}, %q{
  /a/ =~ 'a'
  $a = $~
  Thread.new{
    $b = $~
    /b/ =~ 'b'
    $c = $~
  }.join
  $d = $~
  [$a == $d, $b, $c != $d]
}
assert_equal %q{11}, %q{
  Thread.current[:a] = 1
  Thread.new{
    Thread.current[:a] = 10
    Thread.pass
    Thread.current[:a]
  }.value + Thread.current[:a]
}
assert_normal_exit %q{
  begin
    100.times do |i|
      begin
        th = Thread.start(Thread.current) {|u| u.raise }
        raise
      rescue
      ensure
        th.join
      end
    end
  rescue
  end
}, '[ruby-dev:31371]'

assert_equal 'true', %{
  t = Thread.new { loop {} }
  begin
    pid = fork {
      exit t.status != "run"
    }
    Process.wait pid
    $?.success?
  rescue NotImplementedError
    true
  end
}

assert_equal 'true', %{
  Thread.new{}.join
  begin
    Process.waitpid2 fork{
      Thread.new{
        sleep 0.1
      }.join
    }
    true
  rescue NotImplementedError
    true
  end
}

assert_equal 'ok', %{
  File.write("zzz_t1.rb", <<-END)
      begin
        Thread.new { fork { GC.start } }.join
        pid, status = Process.wait2
        $result = status.success? ? :ok : :ng
      rescue NotImplementedError
        $result = :ok
      end
    END
  require "./zzz_t1.rb"
  $result
}

assert_finish 3, %{
  th = Thread.new {sleep 0.2}
  th.join(0.1)
  th.join
}

assert_finish 3, %{
  require 'timeout'
  th = Thread.new {sleep 0.2}
  begin
    Timeout.timeout(0.1) {th.join}
  rescue Timeout::Error
  end
  th.join
}

assert_normal_exit %q{
  STDERR.reopen(STDOUT)
  exec "/"
}

assert_normal_exit %q{
  (0..10).map {
    Thread.new {
     10000.times {
        Object.new.to_s
      }
    }
  }.each {|t|
    t.join
  }
}

assert_equal 'ok', %q{
  def m
    t = Thread.new { while true; // =~ "" end }
    sleep 0.01
    10.times {
      if /((ab)*(ab)*)*(b)/ =~ "ab"*7
        return :ng if !$4
        return :ng if $~.size != 5
      end
    }
    :ok
  ensure
    Thread.kill t
  end
  m
}, '[ruby-dev:34492]'

assert_normal_exit %q{
  g = enum_for(:local_variables)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = enum_for(:block_given?)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = enum_for(:binding)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = "abc".enum_for(:scan, /./)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  g = Module.enum_for(:new)
  loop { g.next }
}, '[ruby-dev:34128]'

assert_normal_exit %q{
  Thread.new("foo", &Object.method(:class_eval)).join
}, '[ruby-dev:34128]'

assert_equal 'ok', %q{
  begin
    Thread.new { Thread.stop }
    Thread.stop
    :ng
  rescue Exception
    :ok
  end
}

assert_equal 'ok', %q{
  begin
    m1, m2 = Thread::Mutex.new, Thread::Mutex.new
    f1 = f2 = false
    Thread.new { m1.lock; f2 = true; sleep 0.001 until f1; m2.lock }
    m2.lock; f1 = true; sleep 0.001 until f2; m1.lock
    :ng
  rescue Exception
    :ok
  end
}

assert_equal 'ok', %q{
  m = Thread::Mutex.new
  Thread.new { m.lock }; sleep 0.1; m.lock
  :ok
}

assert_equal 'ok', %q{
  m = Thread::Mutex.new
  Thread.new { m.lock }; m.lock
  :ok
}

assert_equal 'ok', %q{
  m = Thread::Mutex.new
  Thread.new { m.lock }.join; m.lock
  :ok
}

assert_equal 'ok', %q{
  m = Thread::Mutex.new
  Thread.new { m.lock; sleep 0.2 }
  sleep 0.1; m.lock
  :ok
}

assert_equal 'ok', %q{
  m = Thread::Mutex.new
  Thread.new { m.lock; sleep 0.2; m.unlock }
  sleep 0.1; m.lock
  :ok
}

assert_equal 'ok', %q{
  t = Thread.new {`echo`}
  t.join
  $? ? :ng : :ok
}, '[ruby-dev:35414]'

assert_equal 'ok', %q{
  begin
    100.times{
      (1..100).map{ Thread.new(true) {|x| x == false } }.each{|th| th.join}
    }
  rescue NoMemoryError, StandardError
  end
  :ok
}

assert_equal 'ok', %{
  File.write("zzz_t2.rb", <<-'end;') # do
      begin
        m = Thread::Mutex.new
        parent = Thread.current
        th1 = Thread.new { m.lock; sleep }
        sleep 0.01 until th1.stop?
        Thread.new do
          sleep 0.01 until parent.stop?
          begin
            fork { GC.start }
          rescue Exception
            parent.raise $!
          end
          th1.run
        end
        m.lock
        pid, status = Process.wait2
        $result = status.success? ? :ok : :ng
      rescue NotImplementedError
        $result = :ok
      end
    end;
  require "./zzz_t2.rb"
  $result
}

assert_finish 3, %q{
  require 'thread'

  lock = Thread::Mutex.new
  cond = Thread::ConditionVariable.new
  t = Thread.new do
    lock.synchronize do
      cond.wait(lock)
    end
  end

  begin
    pid = fork do
      # Child
      STDOUT.write "This is the child process.\n"
      STDOUT.write "Child process exiting.\n"
    end
    Process.waitpid(pid)
  rescue NotImplementedError
  end
}, '[ruby-core:23572]'

assert_equal 'ok', %q{
  begin
    Process.waitpid2(fork {})[1].success? ? 'ok' : 'ng'
  rescue NotImplementedError
    'ok'
  end
}

assert_equal 'foo', %q{
  i = 0
  Thread.start {sleep 1; exit!}
  f = proc {|s, c| /#{c.call; s}/o }
  th2 = Thread.new {
    sleep 0.01 until i == 1
    i = 2
    f.call("bar", proc {sleep 2});
    nil
  }
  th1 = Thread.new {
    f.call("foo", proc {i = 1; sleep 0.01 until i == 2; sleep 0.01})
    nil
  }
  [th1, th2].each {|t| t.join }
  GC.start
  f.call.source
}

assert_normal_exit %q{
  class C
    def inspect
      sleep 0.5
      'C!!'
    end
  end
  Thread.new{
    loop{
      p C.new
    }
  }
  sleep 0.1
}, timeout: 5

# M:N threads waiting on one fd.  These run inside a Ractor because M:N threads
# are enabled by default only outside the main Ractor.

# A second waiter on an fd must not be told it is ready.  Registering it used to
# fail with EEXIST, which was reported to the caller as "the event fired".
assert_equal 'ok', %q{
  Ractor.new do
    r, _w = IO.pipe
    first = Thread.new { r.wait_readable }
    sleep 0.5
    second = Thread.new { r.wait_readable }
    still_waiting = second.join(0.5).nil?
    first.kill
    second.kill
    still_waiting ? 'ok' : 'reported readable with nothing written'
  end.value
}

# ... and a blocking read behind another waiter must sleep rather than spin.
assert_equal 'ok', %q{
  Ractor.new do
    r, _w = IO.pipe
    waiter = Thread.new { r.wait_readable }
    sleep 0.5
    reader = Thread.new { r.read(1) }
    before = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    sleep 1.0
    burned = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - before
    waiter.kill
    reader.kill
    burned < 0.3 ? 'ok' : "burned %.2fs of CPU while idle" % burned
  end.value
}

# Every waiter on the fd is woken, not just the one that registered it.
assert_equal 'ok', %q{
  Ractor.new do
    r, w = IO.pipe
    waiters = 3.times.map { Thread.new { r.wait_readable } }
    sleep 0.5
    w.write('x')
    woken = waiters.count { |t| t.join(5) }
    waiters.each(&:kill)
    woken == 3 ? 'ok' : "only #{woken} of 3 waiters were woken"
  end.value
}

# A read waiting behind another waiter still gets its data.
assert_equal 'ok', %q{
  Ractor.new do
    r, w = IO.pipe
    waiter = Thread.new { r.wait_readable }
    sleep 0.5
    reader = Thread.new { r.read(1) }
    sleep 0.5
    w.write('x')
    got = reader.join(5) ? reader.value : :timeout
    waiter.kill
    got == 'x' ? 'ok' : got.inspect
  end.value
}

# A ractor made runnable while every shared native thread is dedicated to a
# blocking region must still be served: ractor_sched_enq has to wake the timer
# thread, whose untimed sleep otherwise never ends.  [Bug #21504]
assert_equal 'ok', %q{
  lockpath = "mn_enq_wake_#{$$}.lock"
  flagpath = "mn_enq_wake_#{$$}.flag"
  begin
    File.write(lockpath, "")
    lock = File.open(lockpath, "r+")
    lock.flock(File::LOCK_EX)
    r = Ractor.new(lockpath, flagpath) do |lockpath, flagpath|
      f = File.open(lockpath, "r+")
      t = Thread.new do
        sleep 0.2   # let the Ractor.receive below park first
        # Stay off the scheduler until the timer thread is in its untimed sleep;
        # blocking right away would be repaired by the pending 10ms timeout.
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        nil while Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0 < 0.05
        f.flock(File::LOCK_EX)   # the last shared native thread goes dedicated
      end
      msg = Ractor.receive
      File.write(flagpath, "")
      t.join
      msg
    end
    sleep 1   # r is parked, its flock thread is dedicated, the timer sleeps untimed
    r.send(:ok)
    served = false
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until served || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      served = File.exist?(flagpath)
      sleep 0.05
    end
    lock.flock(File::LOCK_UN)
    served ? r.value.to_s : 'the enqueued ractor was never served'
  ensure
    File.unlink(lockpath) rescue nil
    File.unlink(flagpath) rescue nil
  end
}

# Creating a thread when no native thread can be spawned must fail cleanly:
# the thread must not be published to the scheduler before its native thread
# exists, or an existing shared thread runs it to death concurrently with the
# creator's failure path (living-set removal races its own).
assert_equal 'ok', %q{
  can_limit = begin
    Process.setrlimit(:NPROC, Process.getrlimit(:NPROC)[0])
    true
  rescue StandardError, NotImplementedError
    false
  end
  if !can_limit
    'ok'   # cannot make thread creation fail on this platform; nothing to test
  else
    # One warm ractor parks one shared native thread in the pool.  Exactly one:
    # the pool is widened only while snt_cnt < max_cpu, so with two parked
    # threads a 2-CPU host would never attempt pthread_create below and the
    # rlimit would go unnoticed.
    warm = Ractor.new { nil until Ractor.receive == :quit }
    sleep 0.3   # the pool now has a shared native thread parked for the warm ractor
    Process.setrlimit(:NPROC, 1)
    # RLIMIT_NPROC binds neither root (CI containers) nor macOS threads;
    # probe that thread creation actually fails before asserting on it.
    limited = begin
      Thread.new {}.join
      false
    rescue ThreadError
      true
    end
    result =
      if !limited
        'ok'
      else
        errs = 0
        20.times do
          begin
            Ractor.new { :born }
          rescue ThreadError
            errs += 1
          end
        end
        sleep 0.5   # a wrongly-published thread would be served and die about now
        # On a single-CPU host the pool is already at max_cpu, widening is never
        # attempted and nothing raises; everywhere else every attempt must fail.
        # A mixed count means a failed attempt was not rolled back cleanly.
        (errs == 20 || errs == 0) ? 'ok' : "#{errs} of 20 raised"
      end
    warm.send(:quit)
    warm.value
    GC.start
    result
  end
}

# An M:N thread's sleep must survive a spurious wakeup: an interrupt that
# handle_interrupt defers wakes the sleeper, whose status must stay
# THREAD_STOPPED so that sleep_hrtime sleeps the remaining time, as it does
# on a dedicated native thread.
assert_equal 'ok', %q{
  Ractor.new do
    elapsed = nil
    th = Thread.new do
      Thread.handle_interrupt(RuntimeError => :never) do
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sleep 1.0
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      end
    end
    sleep 0.3
    begin th.raise(RuntimeError, "deferred"); rescue RuntimeError; end
    begin th.join; rescue RuntimeError; end
    if elapsed.nil?
      'the sleeper died inside handle_interrupt :never'
    elsif elapsed >= 0.9
      'ok'
    else
      "slept only %.2fs of 1.0s" % elapsed
    end
  end.value
}
