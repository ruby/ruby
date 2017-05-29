require File.expand_path('../../../spec_helper', __FILE__)

describe "Process.setpriority" do
  # Needs a valid version written for Linux
  platform_is :darwin do
    it "sets the scheduling priority for a specified process" do
      priority = Process.getpriority(Process::PRIO_PROCESS, 0)
      IO.popen('-') do |f|
        if f
          pr = Integer(f.gets)
          Integer(f.gets).should == 0
          Integer(f.gets).should == (pr+1)
        else
          pr = Process.getpriority(Process::PRIO_PROCESS, 0)
          p pr
          p Process.setpriority(Process::PRIO_PROCESS, 0, (pr + 1))
          p Process.getpriority(Process::PRIO_PROCESS, 0)
        end
      end
      Process.getpriority(Process::PRIO_PROCESS, 0).should == priority
    end
  end

  # Darwin and FreeBSD don't seem to handle these at all, getting all out of
  # whack with either permission errors or just the wrong value
  platform_is_not :darwin, :freebsd, :windows do
    it "sets the scheduling priority for a specified process group" do
      priority = Process.getpriority(Process::PRIO_PGRP, 0)
      IO.popen('-') do |f|
        if f
          pr = Integer(f.gets)
          Integer(f.gets).should == 0
          Integer(f.gets).should == (pr+1)
        else
          Process.setpgrp
          pr = Process.getpriority(Process::PRIO_PGRP, 0)
          p pr
          p Process.setpriority(Process::PRIO_PGRP, 0, pr + 1)
          p Process.getpriority(Process::PRIO_PGRP, 0)
        end
      end
      Process.getpriority(Process::PRIO_PGRP, 0).should == priority
    end
  end

  platform_is_not :windows do
    as_superuser do
      it "sets the scheduling priority for a specified user" do
        p = Process.getpriority(Process::PRIO_USER, 0)
        Process.setpriority(Process::PRIO_USER, 0, p + 1).should == 0
        Process.getpriority(Process::PRIO_USER, 0).should == (p + 1)
        Process.setpriority(Process::PRIO_USER, 0, p).should == 0
      end
    end
  end

end
