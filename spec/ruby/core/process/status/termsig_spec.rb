require_relative '../../../spec_helper'

describe "Process::Status#termsig" do
  describe "for a child that exited normally" do
    before :each do
      ruby_exe("exit(0)")
    end

    it "returns true" do
      $?.termsig.should be_nil
    end
  end

  describe "for a child that raised SignalException" do
    before :each do
      ruby_exe("raise SignalException, 'SIGTERM'")
    end

    platform_is_not :windows do
      it "returns the signal" do
        $?.termsig.should == Signal.list["TERM"]
      end
    end
  end

  describe "for a child that was sent a signal" do
    before :each do
      ruby_exe("Process.kill(:KILL, $$); exit(42)")
    end

    platform_is_not :windows do
      it "returns the signal" do
        $?.termsig.should == Signal.list["KILL"]
      end
    end

    platform_is :windows do
      it "always returns nil" do
        $?.termsig.should be_nil
      end
    end
  end
end
