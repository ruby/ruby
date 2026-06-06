require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Process.wait" do
  ProcessSpecs.use_system_ruby(self)

  before :all do
    begin
      leaked = Process.waitall
      # Ruby-space should not see PIDs used by rjit
      raise "subprocesses leaked before wait specs: #{leaked}" unless leaked.empty?
    rescue NotImplementedError
    end
  end

  it "raises an Errno::ECHILD if there are no child processes" do
    -> { Process.wait }.should.raise(Errno::ECHILD)
  end

  it "returns its child pid" do
    pid = Process.spawn(ruby_cmd('exit'))
    Process.wait.should == pid
  end

  it "returns nil when the process has not yet completed and WNOHANG is specified" do
    cmd = platform_is(:windows) ? "timeout" : "sleep"
    pid = spawn("#{cmd} 5")
    begin
      Process.wait(pid, Process::WNOHANG).should == nil
      Process.kill("KILL", pid)
    ensure
      Process.wait(pid)
    end
  end

  it "sets $? to a Process::Status" do
    pid = Process.spawn(ruby_cmd('exit'))
    Process.wait
    $?.should.is_a?(Process::Status)
    $?.pid.should == pid
  end

  platform_is_not :windows do
    it "waits for any child process if no pid is given" do
      pid = Process.spawn(ruby_cmd('exit'))
      Process.wait.should == pid
      -> { Process.kill(0, pid) }.should.raise(Errno::ESRCH)
    end

    it "waits for a specific child if a pid is given" do
      pid1 = Process.spawn(ruby_cmd('exit'))
      pid2 = Process.spawn(ruby_cmd('exit'))
      Process.wait(pid2).should == pid2
      Process.wait(pid1).should == pid1
      -> { Process.kill(0, pid1) }.should.raise(Errno::ESRCH)
      -> { Process.kill(0, pid2) }.should.raise(Errno::ESRCH)
    end

    it "coerces the pid to an Integer" do
      pid1 = Process.spawn(ruby_cmd('exit'))
      Process.wait(mock_int(pid1)).should == pid1
      -> { Process.kill(0, pid1) }.should.raise(Errno::ESRCH)
    end

    # This spec is probably system-dependent.
    it "waits for a child whose process group ID is that of the calling process" do
      pid1 = Process.spawn(ruby_cmd('exit'), pgroup: true)
      pid2 = Process.spawn(ruby_cmd('exit'))

      Process.wait(0).should == pid2
      Process.wait.should == pid1
    end
  end

  # This spec is probably system-dependent.
  guard -> { Process.respond_to?(:fork) } do
    it "doesn't block if no child is available when WNOHANG is used" do
      read, write = IO.pipe
      pid = Process.fork do
        read.close
        Signal.trap("TERM") { Process.exit! }
        write << 1
        write.close
        sleep
      end

      Process.wait(pid, Process::WNOHANG).should == nil

      # wait for the child to setup its TERM handler
      write.close
      read.read(1)
      read.close

      Process.kill("TERM", pid)
      Process.wait.should == pid
    end
  end

  platform_is_not :windows do
    it "always accepts flags=0" do
      pid = Process.spawn(ruby_cmd('exit'))
      Process.wait(-1, 0).should == pid
      -> { Process.kill(0, pid) }.should.raise(Errno::ESRCH)
    end
  end
end
