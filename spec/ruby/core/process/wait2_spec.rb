require_relative '../../spec_helper'

describe "Process.wait2" do
  before :all do
    # HACK: this kludge is temporarily necessary because some
    # misbehaving spec somewhere else does not clear processes
    # Note: background processes are unavoidable with MJIT,
    # but we shouldn't reap them from Ruby-space
    begin
      Process.wait(-1, Process::WNOHANG)
      $stderr.puts "Leaked process before wait2 specs! Waiting for it"
      leaked = Process.waitall
      $stderr.puts "leaked before wait2 specs: #{leaked}" unless leaked.empty?
      # Ruby-space should not see PIDs used by mjit
      leaked.should be_empty
    rescue Errno::ECHILD # No child processes
    rescue NotImplementedError
    end
  end

  platform_is_not :windows do
    it "returns the pid and status of child process" do
      pidf = Process.fork { Process.exit! 99 }
      results = Process.wait2
      results.size.should == 2
      pidw, status = results
      pidf.should == pidw
      status.exitstatus.should == 99
    end
  end

  it "raises a StandardError if no child processes exist" do
    -> { Process.wait2 }.should raise_error(Errno::ECHILD)
    -> { Process.wait2 }.should raise_error(StandardError)
  end
end
