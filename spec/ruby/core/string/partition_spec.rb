require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/partition'

describe "String#partition with String" do
  it_behaves_like :string_partition, :partition

  it "returns an array of substrings based on splitting on the given string" do
    "hello world".partition("o").should == ["hell", "o", " world"]
  end

  it "always returns 3 elements" do
    "hello".partition("x").should == ["hello", "", ""]
    "hello".partition("hello").should == ["", "hello", ""]
  end

  it "accepts regexp" do
    "hello!".partition(/l./).should == ["he", "ll", "o!"]
  end

  it "sets global vars if regexp used" do
    "hello!".partition(/(.l)(.o)/)
    $1.should == "el"
    $2.should == "lo"
  end

  it "converts its argument using :to_str" do
    find = mock('l')
    find.should_receive(:to_str).and_return("l")
    "hello".partition(find).should == ["he","l","lo"]
  end

  it "raises an error if not convertible to string" do
    ->{ "hello".partition(5) }.should raise_error(TypeError)
    ->{ "hello".partition(nil) }.should raise_error(TypeError)
  end

  it "takes precedence over a given block" do
    "hello world".partition("o") { true }.should == ["hell", "o", " world"]
  end

  it "handles a pattern in a superset encoding" do
    string = "hello".dup.force_encoding(Encoding::US_ASCII)

    result = string.partition("é")

    result.should == ["hello", "", ""]
    result[0].encoding.should == Encoding::US_ASCII
    result[1].encoding.should == Encoding::US_ASCII
    result[2].encoding.should == Encoding::US_ASCII
  end

  it "handles a pattern in a subset encoding" do
    pattern = "o".dup.force_encoding(Encoding::US_ASCII)

    result = "héllo world".partition(pattern)

    result.should == ["héll", "o", " world"]
    result[0].encoding.should == Encoding::UTF_8
    result[1].encoding.should == Encoding::US_ASCII
    result[2].encoding.should == Encoding::UTF_8
  end
end
