describe :queue_close, shared: true do
  it "may be called multiple times" do
    q = @object.call
    q.close
    q.closed?.should == true
    q.close # no effect
    q.closed?.should == true
  end

  it "returns self" do
    q = @object.call
    q.close.should == q
  end
end
