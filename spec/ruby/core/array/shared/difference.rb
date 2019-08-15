describe :array_binary_difference, shared: true do
  it "creates an array minus any items from other array" do
    [].send(@method, [ 1, 2, 4 ]).should == []
    [1, 2, 4].send(@method, []).should == [1, 2, 4]
    [ 1, 2, 3, 4, 5 ].send(@method, [ 1, 2, 4 ]).should == [3, 5]
  end

  it "removes multiple items on the lhs equal to one on the rhs" do
    [1, 1, 2, 2, 3, 3, 4, 5].send(@method, [1, 2, 4]).should == [3, 3, 5]
  end

  it "properly handles recursive arrays" do
    empty = ArraySpecs.empty_recursive_array
    empty.send(@method, empty).should == []

    [].send(@method, ArraySpecs.recursive_array).should == []

    array = ArraySpecs.recursive_array
    array.send(@method, array).should == []
  end

  it "tries to convert the passed arguments to Arrays using #to_ary" do
    obj = mock('[2,3,3,4]')
    obj.should_receive(:to_ary).and_return([2, 3, 3, 4])
    [1, 1, 2, 2, 3, 4].send(@method, obj).should == [1, 1]
  end

  it "raises a TypeError if the argument cannot be coerced to an Array by calling #to_ary" do
    obj = mock('not an array')
    -> { [1, 2, 3].send(@method, obj) }.should raise_error(TypeError)
  end

  it "does not return subclass instance for Array subclasses" do
    ArraySpecs::MyArray[1, 2, 3].send(@method, []).should be_an_instance_of(Array)
    ArraySpecs::MyArray[1, 2, 3].send(@method, ArraySpecs::MyArray[]).should be_an_instance_of(Array)
    [1, 2, 3].send(@method, ArraySpecs::MyArray[]).should be_an_instance_of(Array)
  end

  it "does not call to_ary on array subclasses" do
    [5, 6, 7].send(@method, ArraySpecs::ToAryArray[7]).should == [5, 6]
  end

  it "removes an item identified as equivalent via #hash and #eql?" do
    obj1 = mock('1')
    obj2 = mock('2')
    obj1.stub!(:hash).and_return(0)
    obj2.stub!(:hash).and_return(0)
    obj1.should_receive(:eql?).at_least(1).and_return(true)

    [obj1].send(@method, [obj2]).should == []
    [obj1, obj1, obj2, obj2].send(@method, [obj2]).should == []
  end

  it "doesn't remove an item with the same hash but not #eql?" do
    obj1 = mock('1')
    obj2 = mock('2')
    obj1.stub!(:hash).and_return(0)
    obj2.stub!(:hash).and_return(0)
    obj1.should_receive(:eql?).at_least(1).and_return(false)

    [obj1].send(@method, [obj2]).should == [obj1]
    [obj1, obj1, obj2, obj2].send(@method, [obj2]).should == [obj1, obj1]
  end

  it "removes an identical item even when its #eql? isn't reflexive" do
    x = mock('x')
    x.stub!(:hash).and_return(42)
    x.stub!(:eql?).and_return(false) # Stubbed for clarity and latitude in implementation; not actually sent by MRI.

    [x].send(@method, [x]).should == []
  end

  it "is not destructive" do
    a = [1, 2, 3]
    a.send(@method, [1])
    a.should == [1, 2, 3]
  end
end
