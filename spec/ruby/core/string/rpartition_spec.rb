require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/partition'

describe "String#rpartition with String" do
  it_behaves_like :string_partition, :rpartition

  it "returns an array of substrings based on splitting on the given string" do
    "hello world".rpartition("o").should == ["hello w", "o", "rld"]
  end

  it "always returns 3 elements" do
    "hello".rpartition("x").should == ["", "", "hello"]
    "hello".rpartition("hello").should == ["", "hello", ""]
  end

  it "returns original string if regexp doesn't match" do
    "hello".rpartition("/x/").should == ["", "", "hello"]
  end

  it "returns new object if doesn't match" do
    str = "hello"
    str.rpartition("/no_match/").last.should_not.equal?(str)
  end

  it "handles multibyte string correctly" do
    "ユーザ@ドメイン".rpartition(/@/).should == ["ユーザ", "@", "ドメイン"]
  end

  it "accepts regexp" do
    "hello!".rpartition(/l./).should == ["hel", "lo", "!"]
  end

  it "affects $~" do
    matched_string = "hello!".rpartition(/l./)[1]
    matched_string.should == $~[0]
  end

  it "converts its argument using :to_str" do
    find = mock('l')
    find.should_receive(:to_str).and_return("l")
    "hello".rpartition(find).should == ["hel","l","o"]
  end

  it "raises an error if not convertible to string" do
    ->{ "hello".rpartition(5) }.should raise_error(TypeError)
    ->{ "hello".rpartition(nil) }.should raise_error(TypeError)
  end

  it "handles a pattern in a superset encoding" do
    string = "hello".dup.force_encoding(Encoding::US_ASCII)

    result = string.rpartition("é")

    result.should == ["", "", "hello"]
    result[0].encoding.should == Encoding::US_ASCII
    result[1].encoding.should == Encoding::US_ASCII
    result[2].encoding.should == Encoding::US_ASCII
  end

  it "handles a pattern in a subset encoding" do
    pattern = "o".dup.force_encoding(Encoding::US_ASCII)

    result = "héllo world".rpartition(pattern)

    result.should == ["héllo w", "o", "rld"]
    result[0].encoding.should == Encoding::UTF_8
    result[1].encoding.should == Encoding::US_ASCII
    result[2].encoding.should == Encoding::UTF_8
  end
end
