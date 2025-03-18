# frozen_string_literal: false
require 'test/unit'
require 'timeout'
require 'tempfile'

class TestSignal < Test::Unit::TestCase
  def test_signal
    begin
      x = 0
      oldtrap = Signal.trap(:INT) {|sig| x = 2 }
      Process.kill :INT, Process.pid
      10.times do
        break if 2 == x
        sleep 0.1
      end
      assert_equal 2, x

      Signal.trap(:INT) { raise "Interrupt" }
      assert_raise_with_message(RuntimeError, /Interrupt/) {
        Process.kill :INT, Process.pid
        sleep 0.1
      }
    ensure
      Signal.trap :INT, oldtrap if oldtrap
    end
  end if Process.respond_to?(:kill)

  def test_signal_process_group
    bug4362 = '[ruby-dev:43169]'
    assert_nothing_raised(bug4362) do
      cmd = [ EnvUtil.rubybin, '--disable=gems' '-e', 'sleep 10' ]
      pid = Process.spawn(*cmd, :pgroup => true)
      Process.kill(:"-TERM", pid)
      Process.waitpid(pid)
      assert_equal(true, $?.signaled?)
      assert_equal(Signal.list["TERM"], $?.termsig)
    end
  end if Process.respond_to?(:kill) and
    Process.respond_to?(:pgroup) # for mswin32

  def test_exit_action
    if Signal.list[sig = "USR1"]
      term = :TERM
    else
      sig = "INT"
      term = :KILL
    end
    IO.popen([EnvUtil.rubybin, '--disable=gems', '-e', <<-"End"], 'r+') do |io|
        Signal.trap(:#{sig}, "EXIT")
        STDOUT.syswrite("a")
        Thread.start { sleep(2) }
        STDIN.sysread(4096)
      End
      pid = io.pid
      io.sysread(1)
      sleep 0.1
      assert_nothing_raised("[ruby-dev:26128]") {
        Process.kill(term, pid)
        begin
          Timeout.timeout(3) {
            Process.waitpid pid
          }
        rescue Timeout::Error
          if term
            Process.kill(term, pid)
            term = (:KILL if term != :KILL)
            retry
          end
          raise
        end
      }
    end
  end if Process.respond_to?(:kill)

  def test_invalid_signal_name
    assert_raise(ArgumentError) { Process.kill(:XXXXXXXXXX, $$) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { Process.kill("\u{30eb 30d3 30fc}", $$) }
  end if Process.respond_to?(:kill)

  def test_signal_exception
    assert_raise(ArgumentError) { SignalException.new }
    assert_raise(ArgumentError) { SignalException.new(-1) }
    assert_raise(ArgumentError) { SignalException.new(:XXXXXXXXXX) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { SignalException.new("\u{30eb 30d3 30fc}") }
    Signal.list.each do |signm, signo|
      next if signm == "EXIT"
      assert_equal(signo, SignalException.new(signm).signo, signm)
      assert_equal(signo, SignalException.new(signm.to_sym).signo, signm)
      assert_equal(signo, SignalException.new(signo).signo, signo)
    end
    e = assert_raise(ArgumentError) {SignalException.new("-SIGEXIT")}
    assert_not_match(/SIG-SIG/, e.message)
  end

  def test_interrupt
    assert_raise(Interrupt) { raise Interrupt.new }
  end

  def test_signal2
    begin
      x = false
      oldtrap = Signal.trap(:INT) {|sig| x = true }
      GC.start

      assert_raise(ArgumentError) { Process.kill }

      Timeout.timeout(10) do
        x = false
        Process.kill(SignalException.new(:INT).signo, $$)
        sleep(0.01) until x

        x = false
        Process.kill("INT", $$)
        sleep(0.01) until x

        x = false
        Process.kill("SIGINT", $$)
        sleep(0.01) until x

        x = false
        o = Object.new
        def o.to_str; "SIGINT"; end
        Process.kill(o, $$)
        sleep(0.01) until x
      end

      assert_raise(ArgumentError) { Process.kill(Object.new, $$) }

    ensure
      Signal.trap(:INT, oldtrap) if oldtrap
    end
  end if Process.respond_to?(:kill)

  def test_trap
    begin
      oldtrap = Signal.trap(:INT) {|sig| }

      assert_raise(ArgumentError) { Signal.trap }

      # FIXME!
      Signal.trap(:INT, nil)
      Signal.trap(:INT, "")
      Signal.trap(:INT, "SIG_IGN")
      Signal.trap(:INT, "IGNORE")

      Signal.trap(:INT, "SIG_DFL")
      Signal.trap(:INT, "SYSTEM_DEFAULT")

      Signal.trap(:INT, "EXIT")

      Signal.trap(:INT, "xxxxxx")
      Signal.trap(:INT, "xxxx")

      Signal.trap(SignalException.new(:INT).signo, "SIG_DFL")

      assert_raise(ArgumentError) { Signal.trap(-1, "xxxx") }

      o = Object.new
      def o.to_str; "SIGINT"; end
      Signal.trap(o, "SIG_DFL")

      assert_raise(ArgumentError) { Signal.trap("XXXXXXXXXX", "SIG_DFL") }

      assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) { Signal.trap("\u{30eb 30d3 30fc}", "SIG_DFL") }

      assert_raise(ArgumentError) { Signal.trap("EXIT\0") {} }
    ensure
      Signal.trap(:INT, oldtrap) if oldtrap
    end
  end if Process.respond_to?(:kill)

  %w"KILL STOP".each do |sig|
    if Signal.list.key?(sig)
      define_method("test_trap_uncatchable_#{sig}") do
        assert_raise(Errno::EINVAL, "SIG#{sig} is not allowed to be caught") { Signal.trap(sig) {} }
      end
    end
  end

  def test_sigexit
    assert_in_out_err([], 'Signal.trap(:EXIT) {print "OK"}', ["OK"])
    assert_in_out_err([], 'Signal.trap("EXIT") {print "OK"}', ["OK"])
    assert_in_out_err([], 'Signal.trap(:SIGEXIT) {print "OK"}', ["OK"])
    assert_in_out_err([], 'Signal.trap("SIGEXIT") {print "OK"}', ["OK"])
    assert_in_out_err([], 'Signal.trap(0) {print "OK"}', ["OK"])
  end

  def test_kill_immediately_before_termination
    Signal.list[sig = "USR1"] or sig = "INT"
    assert_in_out_err(["-e", <<-"end;"], "", %w"foo")
      Signal.trap(:#{sig}) { STDOUT.syswrite("foo") }
      Process.kill :#{sig}, $$
    end;
  end if Process.respond_to?(:kill)

  def test_trap_system_default
    assert_separately([], <<-End)
      trap(:QUIT, "SYSTEM_DEFAULT")
      assert_equal("SYSTEM_DEFAULT", trap(:QUIT, "DEFAULT"))
    End
  end if Signal.list.key?('QUIT')

  def test_reserved_signal
    assert_raise(ArgumentError) {
      Signal.trap(:SEGV) {}
    }
    assert_raise(ArgumentError) {
      Signal.trap(:BUS) {}
    }
    assert_raise(ArgumentError) {
      Signal.trap(:ILL) {}
    }
    assert_raise(ArgumentError) {
      Signal.trap(:FPE) {}
    }
    assert_raise(ArgumentError) {
      Signal.trap(:VTALRM) {}
    }
  end

  def test_signame
    Signal.list.each do |name, num|
      assert_equal(num, Signal.list[Signal.signame(num)], name)
    end
    assert_nil(Signal.signame(-1))
    signums = Signal.list.invert
    assert_nil(Signal.signame((1..1000).find {|num| !signums[num]}))
  end

  def test_signame_delivered
    args = [EnvUtil.rubybin, "--disable=gems", "-e", <<"", :err => File::NULL]
      Signal.trap("INT") do |signo|
        signame = Signal.signame(signo)
        Marshal.dump(signame, STDOUT)
        STDOUT.flush
        exit 0
      end
      Process.kill("INT", $$)
      sleep 1  # wait signal deliver

    10.times do
      IO.popen(args) do |child|
        signame = Marshal.load(child)
        assert_equal("INT", signame)
      end
    end
  end if Process.respond_to?(:kill)

  def test_trap_puts
    assert_in_out_err([], <<-INPUT, ["a"*10000], [])
      Signal.trap(:INT) {
          # for enable internal io mutex
          STDOUT.sync = false
          # larger than internal io buffer
          print "a"*10000
      }
      Process.kill :INT, $$
      sleep 0.1
    INPUT
  end if Process.respond_to?(:kill)

  def test_hup_me
    # [Bug #7951] [ruby-core:52864]
    # This is MRI specific spec. ruby has no guarantee
    # that signal will be deliverd synchronously.
    # This ugly workaround was introduced to don't break
    # compatibility against silly example codes.
    assert_separately([], <<-RUBY)
    trap(:HUP, "DEFAULT")
    assert_raise(SignalException) {
      Process.kill('HUP', Process.pid)
    }
    RUBY
    bug8137 = '[ruby-dev:47182] [Bug #8137]'
    assert_nothing_raised(bug8137) {
      Timeout.timeout(1) {
        Process.kill(0, Process.pid)
      }
    }
  end if Process.respond_to?(:kill) and Signal.list.key?('HUP')

  def test_ignored_interrupt
    bug9820 = '[ruby-dev:48203] [Bug #9820]'
    assert_separately(['-', bug9820], <<-'end;') #    begin
      bug = ARGV.shift
      trap(:INT, "IGNORE")
      assert_nothing_raised(SignalException, bug) do
        Process.kill(:INT, $$)
      end
    end;

    if trap = Signal.list['TRAP']
      bug9820 = '[ruby-dev:48592] [Bug #9820]'
      no_core = "Process.setrlimit(Process::RLIMIT_CORE, 0); " if defined?(Process.setrlimit) && defined?(Process::RLIMIT_CORE)
      status = assert_in_out_err(['-e', "#{no_core}Process.kill(:TRAP, $$)"])
      assert_predicate(status, :signaled?, bug9820)
      assert_equal(trap, status.termsig, bug9820)
    end

    if Signal.list['CONT']
      bug9820 = '[ruby-dev:48606] [Bug #9820]'
      assert_ruby_status(['-e', 'Process.kill(:CONT, $$)'])
    end
  end if Process.respond_to?(:kill)

  def test_signal_list_dedupe_keys
    a = Signal.list.keys.map(&:object_id).sort
    b = Signal.list.keys.map(&:object_id).sort
    assert_equal a, b
  end

  def test_self_stop
    omit unless Process.respond_to?(:fork)
    omit unless defined?(Process::WUNTRACED)

    # Make a process that stops itself
    child_pid = fork do
      Process.kill(:STOP, Process.pid)
    end

    # The parent should be notified about the stop
    _, status = Process.waitpid2(child_pid, Process::WUNTRACED)
    assert status.stopped?

    # It can be continued
    Process.kill(:CONT, child_pid)

    # And the child then runs to completion
    _, status = Process.waitpid2(child_pid)
    assert status.exited?
    assert status.success?
  end

  def test_sigwait_fd_unused
    t = EnvUtil.apply_timeout_scale(0.1)
    assert_separately([], <<-End)
      tgt = $$
      trap(:TERM) { exit(0) }
      e = "Process.daemon; sleep #{t * 2}; Process.kill(:TERM,\#{tgt})"
      term = [ '#{EnvUtil.rubybin}', '--disable=gems', '-e', e ]
      t2 = Thread.new { sleep } # grab sigwait_fd
      Thread.pass until t2.stop?
      Thread.new do
        sleep #{t}
        t2.kill
        t2.join
      end
      Process.spawn(*term)
      # last thread remaining, ensure it can react to SIGTERM
      loop { sleep }
    End
  end if Process.respond_to?(:kill) && Process.respond_to?(:daemon)
end
