describe :sizedqueue_new, shared: true do
  it "raises a TypeError when the given argument is not Numeric" do
    lambda { @object.call("foo") }.should raise_error(TypeError)
    lambda { @object.call(Object.new) }.should raise_error(TypeError)
  end

  it "raises an argument error when no argument is given" do
    lambda { @object.call }.should raise_error(ArgumentError)
  end

  it "raises an argument error when the given argument is zero" do
    lambda { @object.call(0) }.should raise_error(ArgumentError)
  end

  it "raises an argument error when the given argument is negative" do
    lambda { @object.call(-1) }.should raise_error(ArgumentError)
  end
end
