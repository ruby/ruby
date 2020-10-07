# frozen_string_literal: false
require 'test/unit'
require 'fiber'
EnvUtil.suppress_warning {require 'continuation'}
require 'tmpdir'

class TestFiber < Test::Unit::TestCase
  def test_normal
    assert_equal(:ok2,
      Fiber.new{|e|
        assert_equal(:ok1, e)
        Fiber.yield :ok2
      }.resume(:ok1)
    )
    assert_equal([:a, :b], Fiber.new{|a, b| [a, b]}.resume(:a, :b))
  end

  def test_argument
    assert_equal(4, Fiber.new {|i=4| i}.resume)
  end

  def test_term
    assert_equal(:ok, Fiber.new{:ok}.resume)
    assert_equal([:a, :b, :c, :d, :e],
      Fiber.new{
        Fiber.new{
          Fiber.new{
            Fiber.new{
              [:a]
            }.resume + [:b]
          }.resume + [:c]
        }.resume + [:d]
      }.resume + [:e])
  end

  def test_many_fibers
    skip 'This is unstable on GitHub Actions --jit-wait. TODO: debug it' if RubyVM::MJIT.enabled?
    max = 10_000
    assert_equal(max, max.times{
      Fiber.new{}
    })
    GC.start # force collect created fibers
    assert_equal(max,
      max.times{|i|
        Fiber.new{
        }.resume
      }
    )
    GC.start # force collect created fibers
  end

  def test_many_fibers_with_threads
    assert_normal_exit <<-SRC, timeout: 180
      max = 1000
      @cnt = 0
      (1..100).map{|ti|
        Thread.new{
          max.times{|i|
            Fiber.new{
              @cnt += 1
            }.resume
          }
        }
      }.each{|t|
        t.join
      }
    SRC
  end

  def test_error
    assert_raise(ArgumentError){
      Fiber.new # Fiber without block
    }
    f = Fiber.new{}
    Thread.new{
      assert_raise(FiberError){ # Fiber yielding across thread
        f.resume
      }
    }.join
    assert_raise(FiberError){
      f = Fiber.new{}
      f.resume
      f.resume
    }
    assert_raise(RuntimeError){
      Fiber.new{
        @c = callcc{|c| @c = c}
      }.resume
      @c.call # cross fiber callcc
    }
    assert_raise(RuntimeError){
      Fiber.new{
        raise
      }.resume
    }
    assert_raise(FiberError){
      Fiber.yield
    }
    assert_raise(FiberError){
      fib = Fiber.new{
        fib.resume
      }
      fib.resume
    }
    assert_raise(FiberError){
      fib = Fiber.new{
        Fiber.new{
          fib.resume
        }.resume
      }
      fib.resume
    }
    assert_raise(FiberError){
      fib = Fiber.new{}
      fib.raise "raise in unborn fiber"
    }
    assert_raise(FiberError){
      fib = Fiber.new{}
      fib.resume
      fib.raise "raise in dead fiber"
    }
  end

  def test_return
    assert_raise(LocalJumpError){
      Fiber.new do
        return
      end.resume
    }
  end

  def test_throw
    assert_raise(UncaughtThrowError){
      Fiber.new do
        throw :a
      end.resume
    }
  end

  def test_raise
    assert_raise(ZeroDivisionError){
      Fiber.new do
        1/0
      end.resume
    }
    assert_raise(RuntimeError){
      fib = Fiber.new{ Fiber.yield }
      fib.resume
      fib.raise "raise and propagate"
    }
    assert_nothing_raised{
      fib = Fiber.new do
        begin
          Fiber.yield
        rescue
        end
      end
      fib.resume
      fib.raise "rescue in fiber"
    }
    fib = Fiber.new do
      begin
        Fiber.yield
      rescue
        Fiber.yield :ok
      end
    end
    fib.resume
    assert_equal(:ok, fib.raise)
  end

  def test_transfer
    ary = []
    f2 = nil
    f1 = Fiber.new{
      ary << f2.transfer(:foo)
      :ok
    }
    f2 = Fiber.new{
      ary << f1.transfer(:baz)
      :ng
    }
    assert_equal(:ok, f1.transfer)
    assert_equal([:baz], ary)
  end

  def test_terminate_transferred_fiber
    root_fiber = Fiber.current
    log = []
    fa1 = fa2 = fb1 = r1 = nil

    fa1 = Fiber.new{
      fa2 = Fiber.new{
        log << :fa2_terminate
      }
      fa2.resume
      log << :fa1_terminate
    }
    fb1 = Fiber.new{
      fa1.transfer
      log << :fb1_terminate
    }

    r1 = Fiber.new{
      fb1.transfer
      log << :r1_terminate
    }

    r1.resume
    log << :root_terminate

    assert_equal [:fa2_terminate, :fa1_terminate, :r1_terminate, :root_terminate], log
  end

  def test_tls
    #
    def tvar(var, val)
      old = Thread.current[var]
      begin
        Thread.current[var] = val
        yield
      ensure
        Thread.current[var] = old
      end
    end

    fb = Fiber.new {
      assert_equal(nil, Thread.current[:v]); tvar(:v, :x) {
      assert_equal(:x,  Thread.current[:v]);   Fiber.yield
      assert_equal(:x,  Thread.current[:v]); }
      assert_equal(nil, Thread.current[:v]); Fiber.yield
      raise # unreachable
    }

    assert_equal(nil, Thread.current[:v]); tvar(:v,1) {
    assert_equal(1,   Thread.current[:v]);   tvar(:v,3) {
    assert_equal(3,   Thread.current[:v]);     fb.resume
    assert_equal(3,   Thread.current[:v]);   }
    assert_equal(1,   Thread.current[:v]); }
    assert_equal(nil, Thread.current[:v]); fb.resume
    assert_equal(nil, Thread.current[:v]);
  end

  def test_alive
    fib = Fiber.new{Fiber.yield}
    assert_equal(true, fib.alive?)
    fib.resume
    assert_equal(true, fib.alive?)
    fib.resume
    assert_equal(false, fib.alive?)
  end

  def test_resume_self
    f = Fiber.new {f.resume}
    assert_raise(FiberError, '[ruby-core:23651]') {f.transfer}
  end

  def test_fiber_transfer_segv
    assert_normal_exit %q{
      require 'fiber'
      f2 = nil
      f1 = Fiber.new{ f2.resume }
      f2 = Fiber.new{ f1.resume }
      f1.transfer
    }, '[ruby-dev:40833]'
    assert_normal_exit %q{
      require 'fiber'
      Fiber.new{}.resume
      1.times{Fiber.current.transfer}
    }
  end

  def test_resume_root_fiber
    Thread.new do
      assert_raise(FiberError) do
        Fiber.current.resume
      end
    end.join
  end

  def test_gc_root_fiber
    bug4612 = '[ruby-core:35891]'

    assert_normal_exit %q{
      require 'fiber'
      GC.stress = true
      Thread.start{ Fiber.current; nil }.join
      GC.start
    }, bug4612
  end

  def test_mark_fiber
    bug13875 = '[ruby-core:82681]'

    assert_normal_exit %q{
      GC.stress = true
      up = 1.upto(10)
      down = 10.downto(1)
      up.zip(down) {|a, b| a + b == 11 or fail 'oops'}
    }, bug13875
  end

  def test_no_valid_cfp
    bug5083 = '[ruby-dev:44208]'
    assert_equal([], Fiber.new(&Module.method(:nesting)).resume, bug5083)
    assert_instance_of(Class, Fiber.new(&Class.new.method(:undef_method)).resume(:to_s), bug5083)
  end

  def test_prohibit_transfer_to_resuming_fiber
    root_fiber = Fiber.current

    assert_raise(FiberError){
      fiber = Fiber.new{ root_fiber.transfer }
      fiber.resume
    }

    fa1 = Fiber.new{
      fa2 = Fiber.new{ root_fiber.transfer }
    }
    fb1 = Fiber.new{
      fb2 = Fiber.new{ root_fiber.transfer }
    }
    fa1.transfer
    fb1.transfer

    assert_raise(FiberError){
      fa1.transfer
    }
    assert_raise(FiberError){
      fb1.transfer
    }
  end

  def test_prohibit_transfer_to_yielding_fiber
    root_fiber = Fiber.current
    f1 = f2 = f3 = nil

    f1 = Fiber.new{
      f2 = Fiber.new{
        f3 = Fiber.new{
          p f3: Fiber.yield
        }
        f3.resume
      }
      f2.resume
    }
    f1.resume

    assert_raise(FiberError){ f3.transfer 10 }
  end

  def test_prohibit_resume_to_transferring_fiber
    root_fiber = Fiber.current

    assert_raise(FiberError){
      Fiber.new{
        root_fiber.resume
      }.transfer
    }

    f1 = f2 = nil
    f1 = Fiber.new do
      f2.transfer
    end
    f2 = Fiber.new do
      f1.resume # attempt to resume transferring fiber
    end

    assert_raise(FiberError){
      f1.transfer
    }
  end


  def test_fork_from_fiber
    skip 'fork not supported' unless Process.respond_to?(:fork)
    pid = nil
    bug5700 = '[ruby-core:41456]'
    assert_nothing_raised(bug5700) do
      Fiber.new do
        pid = fork do
          xpid = nil
          Fiber.new {
            xpid = fork do
              # enough to trigger GC on old root fiber
              count = 10000
              count = 1000 if /openbsd/i =~ RUBY_PLATFORM
              count.times do
                Fiber.new {}.transfer
                Fiber.new { Fiber.yield }
              end
              exit!(0)
            end
          }.transfer
          _, status = Process.waitpid2(xpid)
          exit!(status.success?)
        end
      end.resume
    end
    pid, status = Process.waitpid2(pid)
    assert_equal(0, status.exitstatus, bug5700)
    assert_equal(false, status.signaled?, bug5700)
  end

  def test_exit_in_fiber
    bug5993 = '[ruby-dev:45218]'
    assert_nothing_raised(bug5993) do
      Thread.new{ Fiber.new{ Thread.exit }.resume; raise "unreachable" }.join
    end
  end

  def test_fatal_in_fiber
    assert_in_out_err(["-r-test-/fatal/rb_fatal", "-e", <<-EOS], "", [], /ok/)
      Fiber.new{
        rb_fatal "ok"
      }.resume
      puts :ng # unreachable.
    EOS
  end

  def test_separate_lastmatch
    bug7678 = '[ruby-core:51331]'
    /a/ =~ "a"
    m1 = $~
    m2 = nil
    Fiber.new do
      /b/ =~ "b"
      m2 = $~
    end.resume
    assert_equal("b", m2[0])
    assert_equal(m1, $~, bug7678)
  end

  def test_separate_lastline
    bug7678 = '[ruby-core:51331]'
    $_ = s1 = "outer"
    s2 = nil
    Fiber.new do
      s2 = "inner"
    end.resume
    assert_equal("inner", s2)
    assert_equal(s1, $_, bug7678)
  end

  def test_new_symbol_proc
    bug = '[ruby-core:80147] [Bug #13313]'
    assert_ruby_status([], "#{<<-"begin;"}\n#{<<-'end;'}", bug)
    begin;
      exit("1" == Fiber.new(&:to_s).resume(1))
    end;
  end

  def test_to_s
    f = Fiber.new do
      assert_match(/resumed/, f.to_s)
      Fiber.yield
    end
    assert_match(/created/, f.to_s)
    f.resume
    assert_match(/suspended/, f.to_s)
    f.resume
    assert_match(/terminated/, f.to_s)
    assert_match(/resumed/, Fiber.current.to_s)
  end

  def test_create_fiber_in_new_thread
    ret = Thread.new{
      Thread.new{
        Fiber.new{Fiber.yield :ok}.resume
      }.value
    }.value
    assert_equal :ok, ret, '[Bug #14642]'
  end

  def test_machine_stack_gc
    assert_normal_exit <<-RUBY, '[Bug #14561]', timeout: 10
      enum = Enumerator.new { |y| y << 1 }
      thread = Thread.new { enum.peek }
      thread.join
      sleep 5     # pause until thread cache wait time runs out. Native thread exits.
      GC.start
    RUBY
  end
end
