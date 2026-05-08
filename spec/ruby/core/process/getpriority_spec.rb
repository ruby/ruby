require_relative '../../spec_helper'

describe "Process.getpriority" do
  platform_is_not :windows do

    it "coerces arguments to Integers" do
      ret = Process.getpriority mock_int(Process::PRIO_PROCESS), mock_int(0)
      ret.should.is_a?(Integer)
    end

    it "gets the scheduling priority for a specified process" do
      Process.getpriority(Process::PRIO_PROCESS, 0).should.is_a?(Integer)
    end

    it "gets the scheduling priority for a specified process group" do
      Process.getpriority(Process::PRIO_PGRP, 0).should.is_a?(Integer)
    end

    it "gets the scheduling priority for a specified user" do
      Process.getpriority(Process::PRIO_USER, 0).should.is_a?(Integer)
    end
  end
end
