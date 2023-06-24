describe :array_pack_numeric_basic, shared: true do
  it "returns an empty String if count is zero" do
    [1].pack(pack_format(0)).should == ""
  end

  it "raises a TypeError when passed nil" do
    -> { [nil].pack(pack_format) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed true" do
    -> { [true].pack(pack_format) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed false" do
    -> { [false].pack(pack_format) }.should raise_error(TypeError)
  end

  it "returns a binary string" do
    [0xFF].pack(pack_format).encoding.should == Encoding::BINARY
    [0xE3, 0x81, 0x82].pack(pack_format(3)).encoding.should == Encoding::BINARY
  end
end

describe :array_pack_integer, shared: true do
  it "raises a TypeError when the object does not respond to #to_int" do
    obj = mock('not an integer')
    -> { [obj].pack(pack_format) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed a String" do
    -> { ["5"].pack(pack_format) }.should raise_error(TypeError)
  end
end

describe :array_pack_float, shared: true do
  it "raises a TypeError if a String does not represent a floating point number" do
    -> { ["a"].pack(pack_format) }.should raise_error(TypeError)
  end

  it "raises a TypeError when the object is not Numeric" do
    obj = Object.new
    -> { [obj].pack(pack_format) }.should raise_error(TypeError, /can't convert Object into Float/)
  end

  it "raises a TypeError when the Numeric object does not respond to #to_f" do
    klass = Class.new(Numeric)
    obj = klass.new
    -> { [obj].pack(pack_format) }.should raise_error(TypeError)
  end
end
