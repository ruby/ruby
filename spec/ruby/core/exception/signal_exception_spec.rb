require_relative '../../spec_helper'

describe "SignalException.new" do
  it "takes a signal number as the first argument" do
    exc = SignalException.new(Signal.list["INT"])
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "SIGINT"
    exc.message.should == "SIGINT"
  end

  it "raises an exception with an invalid signal number" do
    -> { SignalException.new(100000) }.should raise_error(ArgumentError)
  end

  it "takes a signal name without SIG prefix as the first argument" do
    exc = SignalException.new("INT")
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "SIGINT"
    exc.message.should == "SIGINT"
  end

  it "takes a signal name with SIG prefix as the first argument" do
    exc = SignalException.new("SIGINT")
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "SIGINT"
    exc.message.should == "SIGINT"
  end

  it "raises an exception with an invalid signal name" do
    -> { SignalException.new("NONEXISTENT") }.should raise_error(ArgumentError)
  end

  ruby_version_is "2.6" do
    it "raises an exception with an invalid first argument type" do
      -> { SignalException.new(Object.new) }.should raise_error(ArgumentError)
    end
  end

  it "takes a signal symbol without SIG prefix as the first argument" do
    exc = SignalException.new(:INT)
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "SIGINT"
    exc.message.should == "SIGINT"
  end

  it "takes a signal symbol with SIG prefix as the first argument" do
    exc = SignalException.new(:SIGINT)
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "SIGINT"
    exc.message.should == "SIGINT"
  end

  it "raises an exception with an invalid signal name" do
    -> { SignalException.new(:NONEXISTENT) }.should raise_error(ArgumentError)
  end

  it "takes an optional message argument with a signal number" do
    exc = SignalException.new(Signal.list["INT"], "name")
    exc.signo.should == Signal.list["INT"]
    exc.signm.should == "name"
    exc.message.should == "name"
  end

  it "raises an exception for an optional argument with a signal name" do
    -> { SignalException.new("INT","name") }.should raise_error(ArgumentError)
  end
end

describe "rescuing SignalException" do
  it "raises a SignalException when sent a signal" do
    begin
      Process.kill :TERM, Process.pid
      sleep
    rescue SignalException => e
      e.signo.should == Signal.list["TERM"]
      e.signm.should == "SIGTERM"
      e.message.should == "SIGTERM"
    end
  end
end

describe "SignalException" do
  it "can be rescued" do
    ruby_exe(<<-RUBY)
      begin
        raise SignalException, 'SIGKILL'
      rescue SignalException
        exit(0)
      end
      exit(1)
    RUBY

    $?.exitstatus.should == 0
  end

  platform_is_not :windows do
    it "runs after at_exit" do
      output = ruby_exe(<<-RUBY)
        at_exit do
          puts "hello"
          $stdout.flush
        end

        raise SignalException, 'SIGKILL'
      RUBY

      $?.termsig.should == Signal.list.fetch("KILL")
      output.should == "hello\n"
    end

    it "cannot be trapped with Signal.trap" do
      ruby_exe(<<-RUBY)
        Signal.trap("PROF") {}
        raise(SignalException, "PROF")
      RUBY

      $?.termsig.should == Signal.list.fetch("PROF")
    end

    it "self-signals for USR1" do
      ruby_exe("raise(SignalException, 'USR1')")
      $?.termsig.should == Signal.list.fetch('USR1')
    end
  end
end
