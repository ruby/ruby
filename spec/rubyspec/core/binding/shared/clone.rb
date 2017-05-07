describe :binding_clone, shared: true do
  before :each do
    @b1 = BindingSpecs::Demo.new(99).get_binding
    @b2 = @b1.send(@method)
  end

  it "returns a copy of the Binding object" do
    @b1.should_not == @b2

    eval("@secret", @b1).should == eval("@secret", @b2)
    eval("square(2)", @b1).should == eval("square(2)", @b2)
    eval("self.square(2)", @b1).should == eval("self.square(2)", @b2)
    eval("a", @b1).should == eval("a", @b2)
  end

  it "is a shallow copy of the Binding object" do
    eval("a = false", @b1)
    eval("a", @b2).should == false
  end
end
