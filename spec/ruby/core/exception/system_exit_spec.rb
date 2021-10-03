require_relative '../../spec_helper'

describe "SystemExit" do
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
