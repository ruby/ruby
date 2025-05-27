describe :set_inspect, shared: true do
  it "returns a String representation of self" do
    Set[].send(@method).should be_kind_of(String)
    Set[nil, false, true].send(@method).should be_kind_of(String)
    Set[1, 2, 3].send(@method).should be_kind_of(String)
    Set["1", "2", "3"].send(@method).should be_kind_of(String)
    Set[:a, "b", Set[?c]].send(@method).should be_kind_of(String)
  end

  it "does include the elements of the set" do
    Set["1"].send(@method).should == '#<Set: {"1"}>'
  end

  it "puts spaces between the elements" do
    Set["1", "2"].send(@method).should include('", "')
  end

  it "correctly handles cyclic-references" do
    set1 = Set[]
    set2 = Set[set1]
    set1 << set2
    set1.send(@method).should be_kind_of(String)
    set1.send(@method).should include("#<Set: {...}>")
  end

  it "returns a String with the class name" do
    class MySet < Set; end
    MySet[].send(@method).should include("#<MySet: {}>")
  ensure
    Object.send(:remove_const, :MySet) if defined?(MySet)
  end
end
