describe :struct_dup, shared: true do
  it "duplicates members" do
    klass = Struct.new(:foo, :bar)
    instance = klass.new(14, 2)
    duped = instance.send(@method)
    duped.foo.should == 14
    duped.bar.should == 2
  end
end
