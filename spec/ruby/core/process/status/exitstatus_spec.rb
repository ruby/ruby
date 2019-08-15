require_relative '../../../spec_helper'

describe "Process::Status#exitstatus" do
  before :each do
    ruby_exe("exit(42)")
  end

  it "returns the process exit code" do
    $?.exitstatus.should == 42
  end

  describe "for a child that raised SignalException" do
    before :each do
      ruby_exe("raise SignalException, 'SIGTERM'")
    end

    platform_is_not :windows do
      # The exitstatus is not set in these cases. See the termsig_spec
      # for info on where the signal number (SIGTERM) is available.
      it "returns nil" do
        $?.exitstatus.should == nil
      end
    end
  end
end
