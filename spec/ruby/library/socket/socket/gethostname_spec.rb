require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.gethostname" do
  def system_hostname
    # Most platforms implement this POSIX standard:
    `uname -n`.strip
  rescue
    # Only really required for Windows without MSYS/MinGW/Cygwin etc:
    `hostname`.strip
  end

  it "returns the host name" do
    Socket.gethostname.should == system_hostname
  end
end
