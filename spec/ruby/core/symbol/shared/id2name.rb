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

  ruby_version_is "3.4" do
    it "warns about mutating returned string" do
      -> { :bad!.send(@method).upcase! }.should complain(/warning: string returned by :bad!.to_s will be frozen in the future/)
    end

    it "does not warn about mutation when Warning[:deprecated] is false" do
      deprecated = Warning[:deprecated]
      Warning[:deprecated] = false
      -> { :bad!.send(@method).upcase! }.should_not complain
    ensure
      Warning[:deprecated] = deprecated
    end
  end
end
