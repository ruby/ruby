describe :queue_enq, shared: true do
  it "adds an element to the Queue" do
    q = @object.call
    q.size.should == 0
    q.send @method, Object.new
    q.size.should == 1
    q.send @method, Object.new
    q.size.should == 2
  end

  it "is an error for a closed queue" do
    q = @object.call
    q.close
    -> {
      q.send @method, Object.new
    }.should raise_error(ClosedQueueError)
  end
end
