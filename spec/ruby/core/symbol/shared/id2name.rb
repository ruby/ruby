describe :symbol_id2name, shared: true do
  it "returns the string corresponding to self" do
    :rubinius.send(@method).should == "rubinius"
    :squash.send(@method).should == "squash"
    :[].send(@method).should == "[]"
    :@ruby.send(@method).should == "@ruby"
    :@@ruby.send(@method).should == "@@ruby"
  end

  ruby_version_is "2.7" do
    it "returns a frozen String" do
      :my_symbol.to_s.frozen?.should == true
      :"dynamic symbol #{6 * 7}".to_s.frozen?.should == true
    end

    it "always returns the same String for a given Symbol" do
      s1 = :my_symbol.to_s
      s2 = :my_symbol.to_s
      s1.should equal(s2)

      s1 = :"dynamic symbol #{6 * 7}".to_s
      s2 = :"dynamic symbol #{2 * 3 * 7}".to_s
      s1.should equal(s2)
    end
  end
end
