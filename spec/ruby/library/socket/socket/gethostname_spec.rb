require_relative '../spec_helper'

ruby_version_is ""..."4.1" do
  require_relative '../fixtures/classes'

  describe "Socket.gethostname" do
    def system_hostname
      if platform_is_not :windows
        # `uname -n` is the most portable way to get the hostname, as it is a POSIX standard:
        `uname -n`.strip
      else
        # Windows does not have uname, so we use hostname instead:
        `hostname`.strip
      end
    end

    it "returns the host name" do
      Socket.gethostname.should == system_hostname
    end
  end
end
