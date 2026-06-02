describe :strscan_bol, shared: true do
  it "returns true if the scan pointer is at the beginning of the line, false otherwise" do
    s = StringScanner.new("This is a test")
    s.send(@method).should == true
    s.scan(/This/)
    s.send(@method).should == false
    s.terminate
    s.send(@method).should == false

    s = StringScanner.new("hello\nworld")
    s.bol?.should == true
    s.scan(/\w+/)
    s.bol?.should == false
    s.scan(/\n/)
    s.bol?.should == true
    s.unscan
    s.bol?.should == false
  end

  it "returns true if the scan pointer is at the end of the line of an empty string." do
    s = StringScanner.new('')
    s.terminate
    s.send(@method).should == true
  end
end
