require_relative "../../spec_helper"
require_relative 'shared/chars'

describe "String#chars" do
  it_behaves_like :string_chars, :chars

  it "returns an array when no block given" do
    "hello".chars.should == ['h', 'e', 'l', 'l', 'o']
  end

  it "returns Strings in the same encoding as self" do
    "hello".encode("US-ASCII").chars.each do |c|
      c.encoding.should == Encoding::US_ASCII
    end
  end
end
