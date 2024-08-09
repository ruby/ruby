require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#drop_while" do
  # it "removes elements from the start of the hash while the block evaluates to true" do
  #   { a: 1, b: 2, c: 3, d: 4 }.drop_while { |_, n| n < 4 }.should == { d: 4 }
  # end

  # it "removes elements from the start of the hash until the block returns nil" do
  #   { a: 1, b: 2, c: 3, d: nil, e: 5 }.drop_while { |_, n| n }.should == { d: nil, e: 5 }
  # end

  # it "removes elements from the start of the hash until the block returns false" do
  #   { a: 1, b: 2, c: 3, d: false, e: 5 }.drop_while { |_, n| n }.should == { d: false, e: 5 }
  # end

  # it 'returns a Hash instance for Hash subclasses' do
  #   HashSpecs::NewHash.new({ a: 1, b: 2, c: 3, d: 4, e: 5 }).drop_while { |_, n| n < 4 }.should be_an_instance_of(Hash)
  # end
end

describe "Hash#drop_while!" do
  it "returns nil if no changes were made in the hash" do
    { a: 1, b: 2, c: 3 }.drop_while! { false }.should be_nil
  end

  it "removes elements from the start of the hash while the block evaluates to true" do
    a = { a: 1, b: 2, c: 3, d: 4 }
    a.should equal(a.drop_while! { |_, n| n < 4 })
    a.should == { d: 4 }
  end

  it "removes elements from the start of the hash until the block returns nil" do
    a = { a: 1, b: 2, c: 3, d: nil, e: 5 }
    a.should equal(a.drop_while! { |_, n| n })
    a.should == { d: nil, e: 5 }
  end

  it "removes elements from the start of the hash until the block returns false" do
    a = { a: 1, b: 2, c: 3, d: false, e: 5 }
    a.should equal(a.drop_while! { |_, n| n })
    a.should == { d: false, e: 5 }
  end
end