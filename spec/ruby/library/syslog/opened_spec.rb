require_relative '../../spec_helper'

platform_is_not :windows do
  require 'syslog'

  describe "Syslog.opened?" do
    platform_is_not :windows do

      before :each do
        Syslog.opened?.should == false
      end

      after :each do
        Syslog.opened?.should == false
      end

      it "returns true if the log is opened" do
        Syslog.open
        Syslog.opened?.should == true
        Syslog.close
      end

      it "returns false otherwise" do
        Syslog.opened?.should == false
        Syslog.open
        Syslog.close
        Syslog.opened?.should == false
      end

      it "works inside a block" do
        Syslog.open do |s|
          s.opened?.should == true
          Syslog.opened?.should == true
        end
        Syslog.opened?.should == false
      end
    end
  end
end
