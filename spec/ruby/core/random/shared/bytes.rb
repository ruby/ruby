describe :random_bytes, shared: true do
  it "returns a String" do
    @object.bytes(1).should be_an_instance_of(String)
  end

  it "returns a String of the length given as argument" do
    @object.bytes(15).length.should == 15
  end

  it "returns an ASCII-8BIT String" do
    @object.bytes(15).encoding.should == Encoding::ASCII_8BIT
  end

  it "returns a random binary String" do
    @object.bytes(12).should_not == @object.bytes(12)
  end
end
