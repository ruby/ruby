require_relative '../../../spec_helper'

platform_is_not :windows do
  describe "Process::Status#pid" do

    before :each do
      @pid = ruby_exe("print $$").to_i
    end

    it "returns the pid of the process" do
      $?.pid.should == @pid
    end

  end
end
