describe :symbol_id2name, shared: true do
  it "returns the string corresponding to self" do
    :rubinius.send(@method).should == "rubinius"
    :squash.send(@method).should == "squash"
    :[].send(@method).should == "[]"
    :@ruby.send(@method).should == "@ruby"
    :@@ruby.send(@method).should == "@@ruby"
  end

  it "returns a String in the same encoding as self" do
    string = "ruby".encode("US-ASCII")
    symbol = string.to_sym

    symbol.send(@method).encoding.should == Encoding::US_ASCII
  end
end
