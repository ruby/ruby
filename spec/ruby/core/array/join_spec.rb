require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/join'

describe "Array#join" do
  it_behaves_like :array_join_with_string_separator,  :join

  it "does not separate elements when the passed separator is nil" do
    [1, 2, 3].join(nil).should == '123'
  end

  it "calls #to_str to convert the separator to a String" do
    sep = mock("separator")
    sep.should_receive(:to_str).and_return(", ")
    [1, 2].join(sep).should == "1, 2"
  end

  it "does not call #to_str on the separator if the array is empty" do
    sep = mock("separator")
    sep.should_not_receive(:to_str)
    [].join(sep).should == ""
  end

  it "raises a TypeError if the separator cannot be coerced to a String by calling #to_str" do
    obj = mock("not a string")
    -> { [1, 2].join(obj) }.should.raise(TypeError)
  end

  it "raises a TypeError if passed false as the separator" do
    -> { [1, 2].join(false) }.should.raise(TypeError)
  end
end

describe "Array#join with default separator" do
  before :each do
    @separator = $,
  end

  after :each do
    $, = @separator
  end

  it "returns an empty string if the Array is empty" do
    [].join.should == ''
  end

  it "returns a US-ASCII string for an empty Array" do
    [].join.encoding.should == Encoding::US_ASCII
  end

  it "returns a string formed by concatenating each String element separated by $," do
    suppress_warning {
      $, = " | "
      ["1", "2", "3"].join.should == "1 | 2 | 3"
    }
  end

  it "attempts coercion via #to_str first" do
    obj = mock('foo')
    obj.should_receive(:to_str).any_number_of_times.and_return("foo")
    [obj].join.should == "foo"
  end

  it "attempts coercion via #to_ary second" do
    obj = mock('foo')
    obj.should_receive(:to_str).any_number_of_times.and_return(nil)
    obj.should_receive(:to_ary).any_number_of_times.and_return(["foo"])
    [obj].join.should == "foo"
  end

  it "attempts coercion via #to_s third" do
    obj = mock('foo')
    obj.should_receive(:to_str).any_number_of_times.and_return(nil)
    obj.should_receive(:to_ary).any_number_of_times.and_return(nil)
    obj.should_receive(:to_s).any_number_of_times.and_return("foo")
    [obj].join.should == "foo"
  end

  it "raises a NoMethodError if an element does not respond to #to_str, #to_ary, or #to_s" do
    obj = mock('o')
    class << obj; undef :to_s; end
    -> { [1, obj].join }.should.raise(NoMethodError)
  end

  it "raises an ArgumentError when the Array is recursive" do
    -> { ArraySpecs.recursive_array.join }.should.raise(ArgumentError)
    -> { ArraySpecs.head_recursive_array.join }.should.raise(ArgumentError)
    -> { ArraySpecs.empty_recursive_array.join }.should.raise(ArgumentError)
  end

  it "uses the first encoding when other strings are compatible" do
    ary1 = ArraySpecs.array_with_7bit_utf8_and_usascii_strings
    ary2 = ArraySpecs.array_with_usascii_and_7bit_utf8_strings
    ary3 = ArraySpecs.array_with_utf8_and_7bit_binary_strings
    ary4 = ArraySpecs.array_with_usascii_and_7bit_binary_strings

    ary1.join.encoding.should == Encoding::UTF_8
    ary2.join.encoding.should == Encoding::US_ASCII
    ary3.join.encoding.should == Encoding::UTF_8
    ary4.join.encoding.should == Encoding::US_ASCII
  end

  it "uses the widest common encoding when other strings are incompatible" do
    ary1 = ArraySpecs.array_with_utf8_and_usascii_strings
    ary2 = ArraySpecs.array_with_usascii_and_utf8_strings

    ary1.join.encoding.should == Encoding::UTF_8
    ary2.join.encoding.should == Encoding::UTF_8
  end

  it "fails for arrays with incompatibly-encoded strings" do
    ary_utf8_bad_binary = ArraySpecs.array_with_utf8_and_binary_strings

    -> { ary_utf8_bad_binary.join }.should.raise(EncodingError)
  end

  context "when $, is not nil" do
    before do
      suppress_warning do
        $, = '*'
      end
    end

    it "warns" do
      -> { [].join }.should complain(/warning: \$, is set to non-nil value/)
      -> { [].join(nil) }.should complain(/warning: \$, is set to non-nil value/)
    end
  end
end

describe "Array#join with $," do
  before :each do
    @before_separator = $,
  end

  after :each do
    suppress_warning {$, = @before_separator}
  end

  it "separates elements with default separator when the passed separator is nil" do
    suppress_warning {
      $, = "_"
      [1, 2, 3].join(nil).should == '1_2_3'
    }
  end
end
