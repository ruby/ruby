describe :sizedqueue_new, shared: true do
  it "raises a TypeError when the given argument doesn't respond to #to_int" do
    -> { @object.call("12") }.should raise_error(TypeError)
    -> { @object.call(Object.new) }.should raise_error(TypeError)

    @object.call(12.9).max.should == 12
    object = Object.new
    object.define_singleton_method(:to_int) { 42 }
    @object.call(object).max.should == 42
  end

  it "raises an argument error when no argument is given" do
    -> { @object.call }.should raise_error(ArgumentError)
  end

  it "raises an argument error when the given argument is zero" do
    -> { @object.call(0) }.should raise_error(ArgumentError)
  end

  it "raises an argument error when the given argument is negative" do
    -> { @object.call(-1) }.should raise_error(ArgumentError)
  end
end
