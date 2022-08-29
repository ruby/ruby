describe :queue_enq, shared: true do
  it "adds an element to the Queue" do
    q = @object.call
    q.size.should == 0
    q.send @method, Object.new
    q.size.should == 1
    q.send @method, Object.new
    q.size.should == 2
  end

  it "returns self" do
    q = @object.call
    q.send(@method, Object.new).should == q
  end

  it "is an error for a closed queue" do
    q = @object.call
    q.close
    -> {
      q.send @method, Object.new
    }.should raise_error(ClosedQueueError)
  end

  ruby_version_is "3.2" do
    describe "with exception: false" do
      it "raise ArgumentError if exception is anything but true or false" do
        q = @object.call
        q.send(@method, 1, exception: true).should == q
        q.send(@method, 2, exception: false).should == q

        -> { q.send(@method, 3, exception: nil) }.should raise_error(
          ArgumentError,
          "expected true or false as exception: nil",
        )
      end

      it "returns nil for a closed queue" do
        q = @object.call
        q.close
        q.send(@method, Object.new, exception: false).should == nil
      end
    end
  end
end
