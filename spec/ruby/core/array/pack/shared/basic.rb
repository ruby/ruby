describe :array_pack_arguments, shared: true do
  it "raises an ArgumentError if there are fewer elements than the format requires" do
    -> { [].pack(pack_format(1)) }.should raise_error(ArgumentError)
  end
end

describe :array_pack_basic, shared: true do
  before :each do
    @obj = ArraySpecs.universal_pack_object
  end

  it "raises a TypeError when passed nil" do
    -> { [@obj].pack(nil) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed an Integer" do
    -> { [@obj].pack(1) }.should raise_error(TypeError)
  end
end

describe :array_pack_basic_non_float, shared: true do
  before :each do
    @obj = ArraySpecs.universal_pack_object
  end

  it "ignores whitespace in the format string" do
    [@obj, @obj].pack("a \t\n\v\f\r"+pack_format).should be_an_instance_of(String)
  end

  it "ignores comments in the format string" do
    # 2 additional directives ('a') are required for the X directive
    [@obj, @obj, @obj, @obj].pack("aa #{pack_format} # some comment \n#{pack_format}").should be_an_instance_of(String)
  end

  ruby_version_is ""..."3.2" do
    it "warns in verbose mode that a directive is unknown" do
      # additional directive ('a') is required for the X directive
      -> { [@obj, @obj].pack("a R" + pack_format) }.should complain(/unknown pack directive 'R'/, verbose: true)
      -> { [@obj, @obj].pack("a 0" + pack_format) }.should complain(/unknown pack directive '0'/, verbose: true)
      -> { [@obj, @obj].pack("a :" + pack_format) }.should complain(/unknown pack directive ':'/, verbose: true)
    end
  end

  ruby_version_is "3.2"..."3.3" do
    # https://bugs.ruby-lang.org/issues/19150
    # NOTE: it's just a plan of the Ruby core team
    it "warns that a directive is unknown" do
      # additional directive ('a') is required for the X directive
      -> { [@obj, @obj].pack("a R" + pack_format) }.should complain(/unknown pack directive 'R'/)
      -> { [@obj, @obj].pack("a 0" + pack_format) }.should complain(/unknown pack directive '0'/)
      -> { [@obj, @obj].pack("a :" + pack_format) }.should complain(/unknown pack directive ':'/)
    end
  end

  ruby_version_is "3.3" do
    # https://bugs.ruby-lang.org/issues/19150
    # NOTE: Added this case just to not forget about the decision in the ticket
    it "raise ArgumentError when a directive is unknown" do
      # additional directive ('a') is required for the X directive
      -> { [@obj, @obj].pack("a R" + pack_format) }.should raise_error(ArgumentError, /unknown pack directive 'R'/)
      -> { [@obj, @obj].pack("a 0" + pack_format) }.should raise_error(ArgumentError, /unknown pack directive '0'/)
      -> { [@obj, @obj].pack("a :" + pack_format) }.should raise_error(ArgumentError, /unknown pack directive ':'/)
    end
  end

  it "calls #to_str to coerce the directives string" do
    d = mock("pack directive")
    d.should_receive(:to_str).and_return("x"+pack_format)
    [@obj, @obj].pack(d).should be_an_instance_of(String)
  end
end

describe :array_pack_basic_float, shared: true do
  it "ignores whitespace in the format string" do
    [9.3, 4.7].pack(" \t\n\v\f\r"+pack_format).should be_an_instance_of(String)
  end

  it "ignores comments in the format string" do
    [9.3, 4.7].pack(pack_format + "# some comment \n" + pack_format).should be_an_instance_of(String)
  end

  it "calls #to_str to coerce the directives string" do
    d = mock("pack directive")
    d.should_receive(:to_str).and_return("x"+pack_format)
    [1.2, 4.7].pack(d).should be_an_instance_of(String)
  end
end

describe :array_pack_no_platform, shared: true do
  it "raises ArgumentError when the format modifier is '_'" do
    ->{ [1].pack(pack_format("_")) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when the format modifier is '!'" do
    ->{ [1].pack(pack_format("!")) }.should raise_error(ArgumentError)
  end
end
