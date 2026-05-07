require_relative '../../spec_helper'

platform_is_not :windows do
  require 'syslog'

  describe "Syslog.close" do
    platform_is_not :windows do

      before :each do
        Syslog.opened?.should == false
      end

      after :each do
        Syslog.opened?.should == false
      end

      it "closes the log" do
        Syslog.opened?.should == false
        Syslog.open
        Syslog.opened?.should == true
        Syslog.close
        Syslog.opened?.should == false
      end

      it "raises a RuntimeError if the log's already closed" do
        -> { Syslog.close }.should.raise(RuntimeError)
      end

      it "it does not work inside blocks" do
        -> {
          Syslog.open { |s| s.close }
        }.should.raise(RuntimeError)
        Syslog.should_not.opened?
      end

      it "sets the identity to nil" do
        Syslog.open("rubyspec")
        Syslog.ident.should == "rubyspec"
        Syslog.close
        Syslog.ident.should == nil
      end

      it "sets the options to nil" do
        Syslog.open("rubyspec", Syslog::LOG_PID)
        Syslog.options.should == Syslog::LOG_PID
        Syslog.close
        Syslog.options.should == nil
      end

      it "sets the facility to nil" do
        Syslog.open
        Syslog.facility.should == 8
        Syslog.close
        Syslog.facility.should == nil
      end
    end
  end
end
