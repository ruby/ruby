describe :kernel_then, shared: true do
  it "yields self" do
    object = Object.new
    object.send(@method) { |o| o.should equal object }
  end

  it "returns the block return value" do
    object = Object.new
    object.send(@method) { 42 }.should equal 42
  end

  it "returns a sized Enumerator when no block given" do
    object = Object.new
    enum = object.send(@method)
    enum.should be_an_instance_of Enumerator
    enum.size.should equal 1
    enum.peek.should equal object
    enum.first.should equal object
  end
end
