require_relative '../../spec_helper'

platform_is_not :windows do
  require 'syslog'

  describe "Syslog.reopen" do
    it "is an alias of Syslog.open!" do
      Syslog.method(:reopen).should == Syslog.method(:open!)
    end
  end
end
