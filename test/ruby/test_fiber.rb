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
    assert_normal_exit <<-SRC, timeout: 60
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

  def test_prohibit_resume_transferred_fiber
    assert_raise(FiberError){
      root_fiber = Fiber.current
      f = Fiber.new{
        root_fiber.transfer
      }
      f.transfer
      f.resume
    }
    assert_raise(FiberError){
      g=nil
      f=Fiber.new{
        g.resume
        g.resume
      }
      g=Fiber.new{
        f.resume
        f.resume
      }
      f.transfer
    }
  end

  def test_fork_from_fiber
    begin
      pid = Process.fork{}
    rescue NotImplementedError
      return
    else
      Process.wait(pid)
    end
    bug5700 = '[ruby-core:41456]'
    assert_nothing_raised(bug5700) do
      Fiber.new{ pid = fork {} }.resume
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

  def invoke_rec script, vm_stack_size, machine_stack_size, use_length = true
    env = {}
    env['RUBY_FIBER_VM_STACK_SIZE'] = vm_stack_size.to_s if vm_stack_size
    env['RUBY_FIBER_MACHINE_STACK_SIZE'] = machine_stack_size.to_s if machine_stack_size
    out, _ = Dir.mktmpdir("test_fiber") {|tmpdir|
      EnvUtil.invoke_ruby([env, '-e', script], '', true, true, chdir: tmpdir, timeout: 30)
    }
    use_length ? out.length : out
  end

  def test_stack_size
    h_default = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', nil, nil, false))
    h_0 = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 0, 0, false))
    h_large = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 1024 * 1024 * 10, 1024 * 1024 * 10, false))

    assert_operator(h_default[:fiber_vm_stack_size], :>, h_0[:fiber_vm_stack_size])
    assert_operator(h_default[:fiber_vm_stack_size], :<, h_large[:fiber_vm_stack_size])
    assert_operator(h_default[:fiber_machine_stack_size], :>=, h_0[:fiber_machine_stack_size])
    assert_operator(h_default[:fiber_machine_stack_size], :<=, h_large[:fiber_machine_stack_size])

    # check VM machine stack size
    script = '$stdout.sync=true; def rec; print "."; rec; end; Fiber.new{rec}.resume'
    size_default = invoke_rec script, nil, nil
    assert_operator(size_default, :>, 0)
    size_0 = invoke_rec script, 0, nil
    assert_operator(size_default, :>, size_0)
    size_large = invoke_rec script, 1024 * 1024 * 10, nil
    assert_operator(size_default, :<, size_large)

    return if /mswin|mingw/ =~ RUBY_PLATFORM

    # check machine stack size
    # Note that machine stack size may not change size (depend on OSs)
    script = '$stdout.sync=true; def rec; print "."; 1.times{1.times{1.times{rec}}}; end; Fiber.new{rec}.resume'
    vm_stack_size = 1024 * 1024
    size_default = invoke_rec script, vm_stack_size, nil
    size_0 = invoke_rec script, vm_stack_size, 0
    assert_operator(size_default, :>=, size_0)
    size_large = invoke_rec script, vm_stack_size, 1024 * 1024 * 10
    assert_operator(size_default, :<=, size_large)
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
end
