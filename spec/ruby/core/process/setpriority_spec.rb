require_relative '../../spec_helper'

describe "Process.setpriority" do
  platform_is_not :windows do
    it "sets the scheduling priority for a specified process" do
      priority = Process.getpriority(Process::PRIO_PROCESS, 0)

      out = ruby_exe(fixture(__FILE__, "setpriority.rb"), args: "process")
      out = out.lines.map { |l| Integer(l) }
      pr = out[0]
      out.should == [pr, 0, pr+1]

      Process.getpriority(Process::PRIO_PROCESS, 0).should == priority
    end

    # Darwin and FreeBSD don't seem to handle these at all, getting all out of
    # whack with either permission errors or just the wrong value
    platform_is_not :darwin, :freebsd do
      it "sets the scheduling priority for a specified process group" do
        priority = Process.getpriority(Process::PRIO_PGRP, 0)

        out = ruby_exe(fixture(__FILE__, "setpriority.rb"), args: "group")
        out = out.lines.map { |l| Integer(l) }
        pr = out[0]
        out.should == [pr, 0, pr+1]

        Process.getpriority(Process::PRIO_PGRP, 0).should == priority
      end
    end

    as_superuser do
      guard -> {
        prio = Process.getpriority(Process::PRIO_USER, 0)
        # The nice value is a value in the range -20 to 19.
        # This test tries to change the nice value to +-1, so it cannot run if prio == -20 || prio == 19.
        if -20 < prio && prio < 19
          begin
            # Check if we can lower the nice value or not.
            #
            # We are not always able to do it even as a root.
            # Docker container is not always able to do it depending upon the configuration,
            # which cannot know from the container itself.
            Process.setpriority(Process::PRIO_USER, 0, prio - 1)
            Process.setpriority(Process::PRIO_USER, 0, prio)
            true
          rescue Errno::EACCES
            false
          end
        end
      } do
        it "sets the scheduling priority for a specified user" do
          prio = Process.getpriority(Process::PRIO_USER, 0)
          Process.setpriority(Process::PRIO_USER, 0, prio + 1).should == 0
          Process.getpriority(Process::PRIO_USER, 0).should == (prio + 1)
          Process.setpriority(Process::PRIO_USER, 0, prio).should == 0
        end
      end
    end
  end
end
