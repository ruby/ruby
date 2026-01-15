describe :enumerable_minmax, shared: true do
  it "min should return the minimum element" do
    @enum.minmax.should == [4, 10]
    @strs.minmax.should == ["1010", "60"]
  end

  it "returns the minimum when using a block rule" do
    @enum.minmax {|a,b| b <=> a }.should == [10, 4]
    @strs.minmax {|a,b| a.length <=> b.length }.should == ["2", "55555"]
  end

  it "returns [nil, nil] for an empty Enumerable" do
    @empty_enum.minmax.should == [nil, nil]
  end

  it "raises a NoMethodError for elements without #<=>" do
    -> { @incomparable_enum.minmax }.should raise_error(NoMethodError)
  end

  it "raises an ArgumentError when elements are incompatible" do
    -> { @incompatible_enum.minmax }.should raise_error(ArgumentError)
    -> { @enum.minmax{ |a, b| nil } }.should raise_error(ArgumentError)
  end
end
