require_relative '../../spec_helper'

describe "SystemExit" do
  describe "#initialize" do
    it "accepts a status and message" do
      exc = SystemExit.new(42, "message")
      exc.status.should == 42
      exc.message.should == "message"

      exc = SystemExit.new(true, "message")
      exc.status.should == 0
      exc.message.should == "message"

      exc = SystemExit.new(false, "message")
      exc.status.should == 1
      exc.message.should == "message"
    end

    it "accepts a status only" do
      exc = SystemExit.new(42)
      exc.status.should == 42
      exc.message.should == "SystemExit"

      exc = SystemExit.new(true)
      exc.status.should == 0
      exc.message.should == "SystemExit"

      exc = SystemExit.new(false)
      exc.status.should == 1
      exc.message.should == "SystemExit"
    end

    it "accepts a message only" do
      exc = SystemExit.new("message")
      exc.status.should == 0
      exc.message.should == "message"
    end

    it "accepts no arguments" do
      exc = SystemExit.new
      exc.status.should == 0
      exc.message.should == "SystemExit"
    end
  end

  it "sets the exit status and exits silently when raised" do
    code = 'raise SystemExit.new(7)'
    result = ruby_exe(code, args: "2>&1", exit_status: 7)
    result.should == ""
    $?.exitstatus.should == 7
  end

  it "sets the exit status and exits silently when raised when subclassed" do
    code = 'class CustomExit < SystemExit; end; raise CustomExit.new(8)'
    result = ruby_exe(code, args: "2>&1", exit_status: 8)
    result.should == ""
    $?.exitstatus.should == 8
  end
end
