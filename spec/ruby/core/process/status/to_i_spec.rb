require_relative '../../../spec_helper'

describe "Process::Status#to_i" do
  it "returns an integer when the child exits" do
    ruby_exe('exit 48', exit_status: 48)
    $?.to_i.should be_an_instance_of(Integer)
  end

  it "returns an integer when the child is signaled" do
    ruby_exe('raise SignalException, "TERM"', exit_status: platform_is(:windows) ? 3 : nil)
    $?.to_i.should be_an_instance_of(Integer)
  end
end
