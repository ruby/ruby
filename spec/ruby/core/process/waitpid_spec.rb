require_relative '../../spec_helper'

describe "Process.waitpid" do
  it "returns nil when the process has not yet completed and WNOHANG is specified" do
    cmd = platform_is(:windows) ? "timeout" : "sleep"
    pid = spawn("#{cmd} 5")
    begin
      Process.waitpid(pid, Process::WNOHANG).should == nil
      Process.kill("KILL", pid)
    ensure
      Process.wait(pid)
    end
  end
end
