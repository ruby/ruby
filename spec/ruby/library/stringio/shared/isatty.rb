describe :stringio_isatty, shared: true do
  it "returns false" do
    StringIO.new("tty").send(@method).should == false
  end
end
