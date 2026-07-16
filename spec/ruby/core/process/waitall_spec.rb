require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Process.waitall" do
  ProcessSpecs.use_system_ruby(self)

  before :all do
    begin
      Process.waitall
    rescue NotImplementedError
    end
  end

  it "returns an empty array when there are no children" do
    Process.waitall.should == []
  end

  it "takes no arguments" do
    -> { Process.waitall(0) }.should.raise(ArgumentError)
  end

  platform_is_not :windows do
    it "waits for all children and returns an array of pid/status pairs" do
      pids = []
      pids << Process.spawn(ruby_cmd('exit 2'))
      pids << Process.spawn(ruby_cmd('exit 1'))
      pids << Process.spawn(ruby_cmd('exit 0'))
      a = Process.waitall
      pids.each { |pid|
        -> { Process.kill(0, pid) }.should.raise(Errno::ESRCH)
      }

      a.should.is_a?(Array)
      a.size.should == 3
      pids.each { |pid|
        pid_status = a.assoc(pid)
        pid_status.should.is_a?(Array)
        pid_status.size.should == 2
        pid_status.first.should == pid
        pid_status.last.should.is_a?(Process::Status)
      }
    end
  end
end
