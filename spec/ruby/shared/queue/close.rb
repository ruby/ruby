describe :queue_close, shared: true do
  it "may be called multiple times" do
    q = @object.call
    q.close
    q.closed?.should be_true
    q.close # no effect
    q.closed?.should be_true
  end

  it "returns self" do
    q = @object.call
    q.close.should == q
  end
end
