require_relative '../../spec_helper'

platform_is_not :windows do
  describe "Signal.trap" do
    before :each do
      ScratchPad.clear
      @proc = -> {}
      @saved_trap = Signal.trap(:HUP, @proc)
    end

    after :each do
      Signal.trap(:HUP, @saved_trap) if @saved_trap
    end

    it "returns the previous handler" do
      Signal.trap(:HUP, @saved_trap).should equal(@proc)
    end

    it "accepts a block in place of a proc/command argument" do
      done = false

      Signal.trap(:HUP) do
        ScratchPad.record :block_trap
        done = true
      end

      Process.kill :HUP, Process.pid
      Thread.pass until done

      ScratchPad.recorded.should == :block_trap
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
      Process.kill(:HUP, Process.pid).should == 1
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
  end

  describe "Signal.trap" do
    # See man 2 signal
    %w[KILL STOP].each do |signal|
      it "raises ArgumentError or Errno::EINVAL for SIG#{signal}" do
        -> {
          trap(signal, -> {})
        }.should raise_error(StandardError) { |e|
          [ArgumentError, Errno::EINVAL].should include(e.class)
          e.message.should =~ /Invalid argument|Signal already used by VM or OS/
        }
      end
    end

    it "allows to register a handler for all known signals, except reserved signals for which it raises ArgumentError" do
      out = ruby_exe(fixture(__FILE__, "trap_all.rb"), args: "2>&1")
      out.should == "OK\n"
      $?.exitstatus.should == 0
    end

    it "returns 'DEFAULT' for the initial SIGINT handler" do
      ruby_exe('print trap(:INT) { abort }').should == 'DEFAULT'
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
      out = ruby_exe(code)
      status = $?
      out.should == "nil\n"
      status.should.signaled?
      status.termsig.should be_kind_of(Integer)
      Signal.signame(status.termsig).should == "PIPE"
    end
  end
end

describe "Signal.trap" do
  describe "the special EXIT signal code" do
    it "accepts the EXIT code" do
      code = "trap(:EXIT, proc { print 1 })"
      ruby_exe(code).should == "1"
    end

    it "runs the proc before at_exit handlers" do
      code = "at_exit {print 1}; trap(:EXIT, proc {print 2}); at_exit {print 3}"
      ruby_exe(code).should == "231"
    end

    it "can unset the handler" do
      code = "trap(:EXIT, proc { print 1 }); trap(:EXIT, 'DEFAULT')"
      ruby_exe(code).should == ""
    end
  end
end
