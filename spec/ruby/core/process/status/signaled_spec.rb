require_relative '../../../spec_helper'

describe "Process::Status#signaled?" do
  describe "for a cleanly exited child" do
    before :each do
      ruby_exe("exit(0)")
    end

    it "returns false" do
      $?.signaled?.should == false
    end
  end

  describe "for a terminated child" do
    before :each do
      ruby_exe("Process.kill(:KILL, $$); exit(42)", exit_status: platform_is(:windows) ? 0 : :SIGKILL)
    end

    platform_is_not :windows do
      it "returns true" do
        $?.signaled?.should == true
      end
    end

    platform_is :windows do
      it "always returns false" do
        $?.signaled?.should == false
      end
    end
  end
end
