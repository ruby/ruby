describe :process_exit, shared: true do
  it "raises a SystemExit with status 0" do
    -> { @object.exit }.should raise_error(SystemExit) { |e|
      e.status.should == 0
    }
  end

  it "raises a SystemExit with the specified status" do
    [-2**16, -2**8, -8, -1, 0, 1 , 8, 2**8, 2**16].each do |value|
      -> { @object.exit(value) }.should raise_error(SystemExit) { |e|
        e.status.should == value
      }
    end
  end

  it "raises a SystemExit with the specified boolean status" do
    { true => 0, false => 1 }.each do |value, status|
      -> { @object.exit(value) }.should raise_error(SystemExit) { |e|
        e.status.should == status
      }
    end
  end

  it "raises a SystemExit with message 'exit'" do
    -> { @object.exit }.should raise_error(SystemExit) { |e|
      e.message.should == "exit"
    }
  end

  it "tries to convert the passed argument to an Integer using #to_int" do
    obj = mock('5')
    obj.should_receive(:to_int).and_return(5)
    -> { @object.exit(obj) }.should raise_error(SystemExit) { |e|
      e.status.should == 5
    }
  end

  it "converts the passed Float argument to an Integer" do
    { -2.2 => -2, -0.1 => 0, 5.5 => 5, 827.999 => 827 }.each do |value, status|
      -> { @object.exit(value) }.should raise_error(SystemExit) { |e|
        e.status.should == status
      }
    end
  end

  it "raises TypeError if can't convert the argument to an Integer" do
    -> { @object.exit(Object.new) }.should raise_error(TypeError)
    -> { @object.exit('0') }.should raise_error(TypeError)
    -> { @object.exit([0]) }.should raise_error(TypeError)
    -> { @object.exit(nil) }.should raise_error(TypeError)
  end

  it "raises the SystemExit in the main thread if it reaches the top-level handler of another thread" do
    ScratchPad.record []

    ready = false
    t = Thread.new {
      Thread.pass until ready

      begin
        @object.exit 42
      rescue SystemExit => e
        ScratchPad << :in_thread
        raise e
      end
    }

    begin
      ready = true
      sleep
    rescue SystemExit
      ScratchPad << :in_main
    end

    ScratchPad.recorded.should == [:in_thread, :in_main]

    # the thread also keeps the exception as its value
    -> { t.value }.should raise_error(SystemExit)
  end
end

describe :process_exit!, shared: true do
  it "exits with the given status" do
    out = ruby_exe("#{@object}.send(:exit!, 21)", args: '2>&1', exit_status: 21)
    out.should == ""
    $?.exitstatus.should == 21
  end

  it "exits when called from a thread" do
    out = ruby_exe("Thread.new { #{@object}.send(:exit!, 21) }.join; sleep", args: '2>&1', exit_status: 21)
    out.should == ""
    $?.exitstatus.should == 21
  end

  it "exits when called from a fiber" do
    out = ruby_exe("Fiber.new { #{@object}.send(:exit!, 21) }.resume", args: '2>&1', exit_status: 21)
    out.should == ""
    $?.exitstatus.should == 21
  end

  it "skips at_exit handlers" do
    out = ruby_exe("at_exit { STDERR.puts 'at_exit' }; #{@object}.send(:exit!, 21)", args: '2>&1', exit_status: 21)
    out.should == ""
    $?.exitstatus.should == 21
  end

  it "overrides the original exception and exit status when called from #at_exit" do
    code = <<-RUBY
    at_exit do
      STDERR.puts 'in at_exit'
      STDERR.puts "$! is \#{$!.class}:\#{$!.message}"
      #{@object}.send(:exit!, 21)
    end
    raise 'original error'
    RUBY
    out = ruby_exe(code, args: '2>&1', exit_status: 21)
    out.should == "in at_exit\n$! is RuntimeError:original error\n"
    $?.exitstatus.should == 21
  end
end
