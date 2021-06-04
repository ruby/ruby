describe :kernel_sprintf_encoding, shared: true do
  it "can produce a string with valid encoding" do
    string = @method.call("good day %{valid}", valid: "e")
    string.encoding.should == Encoding::UTF_8
    string.valid_encoding?.should be_true
  end

  it "can produce a string with invalid encoding" do
    string = @method.call("good day %{invalid}", invalid: "\x80")
    string.encoding.should == Encoding::UTF_8
    string.valid_encoding?.should be_false
  end

  it "returns a String in the same encoding as the format String if compatible" do
    string = "%s".force_encoding(Encoding::KOI8_U)
    result = @method.call(string, "dogs")
    result.encoding.should equal(Encoding::KOI8_U)
  end

  it "returns a String in the argument's encoding if format encoding is more restrictive" do
    string = "foo %s".force_encoding(Encoding::US_ASCII)
    argument = "b\303\274r".force_encoding(Encoding::UTF_8)

    result = @method.call(string, argument)
    result.encoding.should equal(Encoding::UTF_8)
  end

  it "raises Encoding::CompatibilityError if both encodings are ASCII compatible and there ano not ASCII characters" do
    string = "Ä %s".encode('windows-1252')
    argument = "Ђ".encode('windows-1251')

    -> {
      @method.call(string, argument)
    }.should raise_error(Encoding::CompatibilityError)
  end
end
