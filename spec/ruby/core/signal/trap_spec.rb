require_relative '../../spec_helper'

describe "Signal.trap" do
  platform_is_not :windows do
    before :each do
      ScratchPad.clear
      @proc = -> {}
      @saved_trap = Signal.trap(:HUP, @proc)
      @hup_number = Signal.list["HUP"]
    end

    after :each do
      Signal.trap(:HUP, @saved_trap) if @saved_trap
    end

    it "returns the previous handler" do
      Signal.trap(:HUP, @saved_trap).should equal(@proc)
    end

    it "accepts a block" do
      done = false

      Signal.trap(:HUP) do |signo|
        signo.should == @hup_number
        ScratchPad.record :block_trap
        done = true
      end

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :block_trap
    end

    it "accepts a proc" do
      done = false

      handler = -> signo {
        signo.should == @hup_number
        ScratchPad.record :proc_trap
        done = true
      }

      Signal.trap(:HUP, handler)

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :proc_trap
    end

    it "accepts a method" do
      done = false

      handler_class = Class.new
      hup_number = @hup_number

      handler_class.define_method :handler_method do |signo|
        signo.should == hup_number
        ScratchPad.record :method_trap
        done = true
      end

      handler_method = handler_class.new.method(:handler_method)

      Signal.trap(:HUP, handler_method)

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :method_trap
    end

    it "accepts anything you can call" do
      done = false

      callable = Object.new
      hup_number = @hup_number

      callable.singleton_class.define_method :call do |signo|
        signo.should == hup_number
        ScratchPad.record :callable_trap
        done = true
      end

      Signal.trap(:HUP, callable)

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :callable_trap
    end

    it "raises an exception for a non-callable at the point of use" do
      not_callable = Object.new
      Signal.trap(:HUP, not_callable)
      -> {
        Process.kill :HUP, Process.pid
        loop { Thread.pass }
      }.should raise_error(NoMethodError)
    end

    it "accepts a non-callable that becomes callable when used" do
      done = false

      late_callable = Object.new
      hup_number = @hup_number

      Signal.trap(:HUP, late_callable)

      late_callable.singleton_class.define_method :call do |signo|
        signo.should == hup_number
        ScratchPad.record :late_callable_trap
        done = true
      end

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :late_callable_trap
    end

    it "is possible to create a new Thread when the handler runs" do
      done = false

      Signal.trap(:HUP) do
        thr = Thread.new { }
        thr.join
        ScratchPad.record(thr.group == Thread.main.group)

        done = true
      end

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should be_true
    end

    it "registers an handler doing nothing with :IGNORE" do
      Signal.trap :HUP, :IGNORE
      Signal.trap(:HUP, @saved_trap).should == "IGNORE"
    end

    it "can register a new handler after :IGNORE" do
      Signal.trap :HUP, :IGNORE

      done = false
      Signal.trap(:HUP) do
        ScratchPad.record :block_trap
        done = true
      end

      Process.kill(:HUP, Process.pid).should == 1
      Thread.pass until done
      ScratchPad.recorded.should == :block_trap
    end

    it "ignores the signal when passed nil" do
      Signal.trap :HUP, nil
      Signal.trap(:HUP, @saved_trap).should be_nil
    end

    it "accepts :DEFAULT in place of a proc" do
      Signal.trap :HUP, :DEFAULT
      Signal.trap(:HUP, @saved_trap).should == "DEFAULT"
    end

    it "accepts :SIG_DFL in place of a proc" do
      Signal.trap :HUP, :SIG_DFL
      Signal.trap(:HUP, @saved_trap).should == "DEFAULT"
    end

    it "accepts :SIG_IGN in place of a proc" do
      Signal.trap :HUP, :SIG_IGN
      Signal.trap(:HUP, @saved_trap).should == "IGNORE"
    end

    it "accepts :IGNORE in place of a proc" do
      Signal.trap :HUP, :IGNORE
      Signal.trap(:HUP, @saved_trap).should == "IGNORE"
    end

    it "accepts 'SIG_DFL' in place of a proc" do
      Signal.trap :HUP, "SIG_DFL"
      Signal.trap(:HUP, @saved_trap).should == "DEFAULT"
    end

    it "accepts 'DEFAULT' in place of a proc" do
      Signal.trap :HUP, "DEFAULT"
      Signal.trap(:HUP, @saved_trap).should == "DEFAULT"
    end

    it "accepts 'SIG_IGN' in place of a proc" do
      Signal.trap :HUP, "SIG_IGN"
      Signal.trap(:HUP, @saved_trap).should == "IGNORE"
    end

    it "accepts 'IGNORE' in place of a proc" do
      Signal.trap :HUP, "IGNORE"
      Signal.trap(:HUP, @saved_trap).should == "IGNORE"
    end

    it "accepts long names as Strings" do
      Signal.trap "SIGHUP", @proc
      Signal.trap("SIGHUP", @saved_trap).should equal(@proc)
    end

    it "accepts short names as Strings" do
      Signal.trap "HUP", @proc
      Signal.trap("HUP", @saved_trap).should equal(@proc)
    end

    it "accepts long names as Symbols" do
      Signal.trap :SIGHUP, @proc
      Signal.trap(:SIGHUP, @saved_trap).should equal(@proc)
    end

    it "accepts short names as Symbols" do
      Signal.trap :HUP, @proc
      Signal.trap(:HUP, @saved_trap).should equal(@proc)
    end

    it "calls #to_str on an object to convert to a String" do
      obj = mock("signal")
      obj.should_receive(:to_str).exactly(2).times.and_return("HUP")
      Signal.trap obj, @proc
      Signal.trap(obj, @saved_trap).should equal(@proc)
    end

    it "accepts Integer values" do
      hup = Signal.list["HUP"]
      Signal.trap hup, @proc
      Signal.trap(hup, @saved_trap).should equal(@proc)
    end

    it "does not call #to_int on an object to convert to an Integer" do
      obj = mock("signal")
      obj.should_not_receive(:to_int)
      -> { Signal.trap obj, @proc }.should raise_error(ArgumentError, /bad signal type/)
    end

    it "raises ArgumentError when passed unknown signal" do
      -> { Signal.trap(300) { } }.should raise_error(ArgumentError, "invalid signal number (300)")
      -> { Signal.trap("USR10") { } }.should raise_error(ArgumentError, /\Aunsupported signal [`']SIGUSR10'\z/)
      -> { Signal.trap("SIGUSR10") { } }.should raise_error(ArgumentError, /\Aunsupported signal [`']SIGUSR10'\z/)
    end

    it "raises ArgumentError when passed signal is not Integer, String or Symbol" do
      -> { Signal.trap(nil) { } }.should raise_error(ArgumentError, "bad signal type NilClass")
      -> { Signal.trap(100.0) { } }.should raise_error(ArgumentError, "bad signal type Float")
      -> { Signal.trap(Rational(100)) { } }.should raise_error(ArgumentError, "bad signal type Rational")
    end

    # See man 2 signal
    %w[KILL STOP].each do |signal|
      it "raises ArgumentError or Errno::EINVAL for SIG#{signal}" do
        -> {
          Signal.trap(signal, -> {})
        }.should raise_error(StandardError) { |e|
          [ArgumentError, Errno::EINVAL].should include(e.class)
          e.message.should =~ /Invalid argument|Signal already used by VM or OS/
        }
      end
    end

    %w[SEGV BUS ILL FPE VTALRM].each do |signal|
      it "raises ArgumentError for SIG#{signal} which is reserved by Ruby" do
        -> {
          Signal.trap(signal, -> {})
        }.should raise_error(ArgumentError, "can't trap reserved signal: SIG#{signal}")
      end
    end

    it "allows to register a handler for all known signals, except reserved signals for which it raises ArgumentError" do
      out = ruby_exe(fixture(__FILE__, "trap_all.rb"), args: "2>&1")
      out.should == "OK\n"
      $?.exitstatus.should == 0
    end

    it "returns 'DEFAULT' for the initial SIGINT handler" do
      ruby_exe("print Signal.trap(:INT) { abort }").should == 'DEFAULT'
    end

    it "returns SYSTEM_DEFAULT if passed DEFAULT and no handler was ever set" do
      Signal.trap("PROF", "DEFAULT").should == "SYSTEM_DEFAULT"
    end

    it "accepts 'SYSTEM_DEFAULT' and uses the OS handler for SIGPIPE" do
      code = <<-RUBY
        p Signal.trap('PIPE', 'SYSTEM_DEFAULT')
        r, w = IO.pipe
        r.close
        loop { w.write("a"*1024) }
      RUBY
      out = ruby_exe(code, exit_status: :SIGPIPE)
      status = $?
      out.should == "nil\n"
      status.should.signaled?
    end
  end

  describe "the special EXIT signal code" do
    it "accepts the EXIT code" do
      code = "Signal.trap(:EXIT, proc { print 1 })"
      ruby_exe(code).should == "1"
    end

    it "runs the proc before at_exit handlers" do
      code = "at_exit {print 1}; Signal.trap(:EXIT, proc {print 2}); at_exit {print 3}"
      ruby_exe(code).should == "231"
    end

    it "can unset the handler" do
      code = "Signal.trap(:EXIT, proc { print 1 }); Signal.trap(:EXIT, 'DEFAULT')"
      ruby_exe(code).should == ""
    end
  end

end
