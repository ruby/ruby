require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Process.wait2" do
  ProcessSpecs.use_system_ruby(self)

  before :all do
    # HACK: this kludge is temporarily necessary because some
    # misbehaving spec somewhere else does not clear processes
    # Note: background processes are unavoidable with RJIT,
    # but we shouldn't reap them from Ruby-space
    begin
      Process.wait(-1, Process::WNOHANG)
      $stderr.puts "Leaked process before wait2 specs! Waiting for it"
      leaked = Process.waitall
      $stderr.puts "leaked before wait2 specs: #{leaked}" unless leaked.empty?
      # Ruby-space should not see PIDs used by rjit
      leaked.should.empty?
    rescue Errno::ECHILD # No child processes
    rescue NotImplementedError
    end
  end

  it "returns the pid and status of child process" do
    pidf = Process.spawn(*ruby_exe, "-e", "exit 99")
    results = Process.wait2
    results.size.should == 2
    pidw, status = results
    pidf.should == pidw
    status.exitstatus.should == 99
  end

  it "raises a StandardError if no child processes exist" do
    -> { Process.wait2 }.should.raise(Errno::ECHILD)
    -> { Process.wait2 }.should.raise(StandardError)
  end

  it "returns nil if the child process is still running when given the WNOHANG flag" do
    IO.popen(ruby_cmd('STDIN.getbyte'), "w") do |io|
      pid, status = Process.wait2(io.pid, Process::WNOHANG)
      pid.should == nil
      status.should == nil
      io.write('a')
    end
  end
end
