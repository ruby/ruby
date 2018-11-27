describe :sizedqueue_max, shared: true do
  it "returns the size of the queue" do
    q = @object.call(5)
    q.max.should == 5
  end
end

describe :sizedqueue_max=, shared: true do
  it "sets the size of the queue" do
    q = @object.call(5)
    q.max.should == 5
    q.max = 10
    q.max.should == 10
  end

  it "does not remove items already in the queue beyond the maximum" do
    q = @object.call(5)
    q.enq 1
    q.enq 2
    q.enq 3
    q.max = 2
    (q.size > q.max).should be_true
    q.deq.should == 1
    q.deq.should == 2
    q.deq.should == 3
  end

  it "raises a TypeError when given a non-numeric value" do
    q = @object.call(5)
    lambda { q.max = "foo" }.should raise_error(TypeError)
    lambda { q.max = Object.new }.should raise_error(TypeError)
  end

  it "raises an argument error when set to zero" do
    q = @object.call(5)
    q.max.should == 5
    lambda { q.max = 0 }.should raise_error(ArgumentError)
    q.max.should == 5
  end

  it "raises an argument error when set to a negative number" do
    q = @object.call(5)
    q.max.should == 5
    lambda { q.max = -1 }.should raise_error(ArgumentError)
    q.max.should == 5
  end
end
