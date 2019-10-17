describe :proc_dup, shared: true do
  it "returns a copy of self" do
    a = -> { "hello" }
    b = a.send(@method)

    a.should_not equal(b)

    a.call.should == b.call
  end
end
