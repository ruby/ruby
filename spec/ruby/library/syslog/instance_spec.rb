require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do

  platform_is_not :windows do
    require 'syslog'

    describe "Syslog.instance" do
      platform_is_not :windows do
        it "returns the module" do
          Syslog.instance.should == Syslog
        end
      end
    end
  end
end
