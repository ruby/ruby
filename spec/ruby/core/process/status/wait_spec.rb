require_relative '../../../spec_helper'
require_relative '../fixtures/common'

ruby_version_is "3.0" do
  describe "Process::Status.wait" do
    ProcessSpecs.use_system_ruby(self)

    before :all do
      begin
        leaked = Process.waitall
        # Ruby-space should not see PIDs used by mjit
        raise "subprocesses leaked before wait specs: #{leaked}" unless leaked.empty?
      rescue NotImplementedError
      end
    end

    it "returns a status with pid -1 if there are no child processes" do
      Process::Status.wait.pid.should == -1
    end

    platform_is_not :windows do
      it "returns a status with its child pid" do
        pid = Process.spawn(ruby_cmd('exit'))
        status = Process::Status.wait
        status.should be_an_instance_of(Process::Status)
        status.pid.should == pid
      end

      it "should not set $? to the Process::Status" do
        pid = Process.spawn(ruby_cmd('exit'))
        status = Process::Status.wait
        $?.should_not equal(status)
      end

      it "should not change the value of $?" do
        pid = Process.spawn(ruby_cmd('exit'))
        Process.wait
        status = $?
        Process::Status.wait
        status.should equal($?)
      end

      it "waits for any child process if no pid is given" do
        pid = Process.spawn(ruby_cmd('exit'))
        Process::Status.wait.pid.should == pid
        -> { Process.kill(0, pid) }.should raise_error(Errno::ESRCH)
      end

      it "waits for a specific child if a pid is given" do
        pid1 = Process.spawn(ruby_cmd('exit'))
        pid2 = Process.spawn(ruby_cmd('exit'))
        Process::Status.wait(pid2).pid.should == pid2
        Process::Status.wait(pid1).pid.should == pid1
        -> { Process.kill(0, pid1) }.should raise_error(Errno::ESRCH)
        -> { Process.kill(0, pid2) }.should raise_error(Errno::ESRCH)
      end

      it "coerces the pid to an Integer" do
        pid1 = Process.spawn(ruby_cmd('exit'))
        Process::Status.wait(mock_int(pid1)).pid.should == pid1
        -> { Process.kill(0, pid1) }.should raise_error(Errno::ESRCH)
      end

      # This spec is probably system-dependent.
      it "waits for a child whose process group ID is that of the calling process" do
        pid1 = Process.spawn(ruby_cmd('exit'), pgroup: true)
        pid2 = Process.spawn(ruby_cmd('exit'))

        Process::Status.wait(0).pid.should == pid2
        Process::Status.wait.pid.should == pid1
      end

      # This spec is probably system-dependent.
      it "doesn't block if no child is available when WNOHANG is used" do
        read, write = IO.pipe
        pid = Process.fork do
          read.close
          Signal.trap("TERM") { Process.exit! }
          write << 1
          write.close
          sleep
        end

        Process::Status.wait(pid, Process::WNOHANG).should be_nil

        # wait for the child to setup its TERM handler
        write.close
        read.read(1)
        read.close

        Process.kill("TERM", pid)
        Process::Status.wait.pid.should == pid
      end

      it "always accepts flags=0" do
        pid = Process.spawn(ruby_cmd('exit'))
        Process::Status.wait(-1, 0).pid.should == pid
        -> { Process.kill(0, pid) }.should raise_error(Errno::ESRCH)
      end
    end
  end
end
