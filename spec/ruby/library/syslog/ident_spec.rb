require_relative '../../spec_helper'

platform_is_not :windows do
  require 'syslog'

  describe "Syslog.ident" do
    platform_is_not :windows do

      before :each do
        Syslog.opened?.should be_false
      end

      after :each do
        Syslog.opened?.should be_false
      end

      it "returns the logging identity" do
        Syslog.open("rubyspec")
        Syslog.ident.should == "rubyspec"
        Syslog.close
      end

      it "returns nil if the log is closed" do
        Syslog.should_not.opened?
        Syslog.ident.should == nil
      end

      it "defaults to $0" do
        Syslog.open
        Syslog.ident.should == $0
        Syslog.close
      end
    end
  end
end
