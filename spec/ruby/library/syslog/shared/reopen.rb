describe :syslog_reopen, shared: true do
  platform_is_not :windows do
    before :each do
      Syslog.opened?.should == false
    end

    after :each do
      Syslog.opened?.should == false
    end

    it "reopens the log" do
      Syslog.open
      -> { Syslog.send(@method)}.should_not.raise
      Syslog.opened?.should == true
      Syslog.close
    end

    it "fails with RuntimeError if the log is closed" do
      -> { Syslog.send(@method)}.should.raise(RuntimeError)
    end

    it "receives the same parameters as Syslog.open" do
      Syslog.open
      Syslog.send(@method, "rubyspec", 3, 8) do |s|
        s.should == Syslog
        s.ident.should == "rubyspec"
        s.options.should == 3
        s.facility.should == Syslog::LOG_USER
        s.opened?.should == true
      end
      Syslog.opened?.should == false
    end

    it "returns the module" do
      Syslog.open
      Syslog.send(@method).should == Syslog
      Syslog.close
    end
  end
end
