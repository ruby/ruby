require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/concat'

describe "String#<<" do
  it_behaves_like :string_concat, :<<
  it_behaves_like :string_concat_encoding, :<<

  it "raises an ArgumentError when given the incorrect number of arguments" do
    -> { "hello".send(:<<) }.should raise_error(ArgumentError)
    -> { "hello".send(:<<, "one", "two") }.should raise_error(ArgumentError)
  end
end
