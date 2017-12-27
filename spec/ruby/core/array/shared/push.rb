describe :array_push, shared: true do
  it "appends the arguments to the array" do
    a = [ "a", "b", "c" ]
    a.send(@method, "d", "e", "f").should equal(a)
    a.send(@method).should == ["a", "b", "c", "d", "e", "f"]
    a.send(@method, 5)
    a.should == ["a", "b", "c", "d", "e", "f", 5]

    a = [0, 1]
    a.send(@method, 2)
    a.should == [0, 1, 2]
  end

  it "isn't confused by previous shift" do
    a = [ "a", "b", "c" ]
    a.shift
    a.send(@method, "foo")
    a.should == ["b", "c", "foo"]
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.send(@method, :last).should == [empty, :last]

    array = ArraySpecs.recursive_array
    array.send(@method, :last).should == [1, 'two', 3.0, array, array, array, array, array, :last]
  end

  it "raises a #{frozen_error_class} on a frozen array" do
    lambda { ArraySpecs.frozen_array.send(@method, 1) }.should raise_error(frozen_error_class)
    lambda { ArraySpecs.frozen_array.send(@method) }.should raise_error(frozen_error_class)
  end
end
