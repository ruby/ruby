require_relative 'shared/chars'
require_relative 'shared/each_char_without_block'

describe "String#chars" do
  it_behaves_like :string_chars, :chars

  it "returns an array when no block given" do
    "hello".chars.should == ['h', 'e', 'l', 'l', 'o']
  end
end
