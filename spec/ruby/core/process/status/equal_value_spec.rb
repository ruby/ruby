require_relative '../../../spec_helper'

describe "Process::Status#==" do
  it "returns true when compared to the integer status of an exited child" do
    ruby_exe("exit(29)", exit_status: 29)
    $?.to_i.should == $?
    $?.should == $?.to_i
  end

  it "returns true when compared to the integer status of a terminated child" do
    ruby_exe("Process.kill(:KILL, $$); exit(29)", exit_status: platform_is(:windows) ? 0 : nil)
    $?.to_i.should == $?
    $?.should == $?.to_i
  end
end
