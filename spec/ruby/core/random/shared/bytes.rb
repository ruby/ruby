describe :random_bytes, shared: true do
  it "returns a String" do
    @object.send(@method, 1).should be_an_instance_of(String)
  end

  it "returns a String of the length given as argument" do
    @object.send(@method, 15).length.should == 15
  end

  it "returns a binary String" do
    @object.send(@method, 15).encoding.should == Encoding::BINARY
  end

  it "returns a random binary String" do
    @object.send(@method, 12).should_not == @object.send(@method, 12)
  end
end
