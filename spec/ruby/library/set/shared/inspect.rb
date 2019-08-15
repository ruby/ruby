describe "set_inspect", shared: true do
  it "returns a String representation of self" do
    Set[].send(@method).should be_kind_of(String)
    Set[nil, false, true].send(@method).should be_kind_of(String)
    Set[1, 2, 3].send(@method).should be_kind_of(String)
    Set["1", "2", "3"].send(@method).should be_kind_of(String)
    Set[:a, "b", Set[?c]].send(@method).should be_kind_of(String)
  end

  it "correctly handles self-references" do
    (set = Set[]) << set
    set.send(@method).should be_kind_of(String)
    set.send(@method).should include("#<Set: {...}>")
  end
end
