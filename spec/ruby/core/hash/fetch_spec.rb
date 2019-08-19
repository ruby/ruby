require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../../../shared/hash/key_error', __FILE__)

describe "Hash#fetch" do
  context "when the key is not found" do
    it_behaves_like :key_error, ->(obj, key) { obj.fetch(key) }, Hash.new(a: 5)
    it_behaves_like :key_error, ->(obj, key) { obj.fetch(key) }, {}
    it_behaves_like :key_error, ->(obj, key) { obj.fetch(key) }, Hash.new { 5 }
    it_behaves_like :key_error, ->(obj, key) { obj.fetch(key) }, Hash.new(5)
  end

  it "returns the value for key" do
    { a: 1, b: -1 }.fetch(:b).should == -1
  end

  it "returns default if key is not found when passed a default" do
    {}.fetch(:a, nil).should == nil
    {}.fetch(:a, 'not here!').should == "not here!"
    { a: nil }.fetch(:a, 'not here!').should == nil
  end

  it "returns value of block if key is not found when passed a block" do
    {}.fetch('a') { |k| k + '!' }.should == "a!"
  end

  it "gives precedence to the default block over the default argument when passed both" do
    lambda {
      @result = {}.fetch(9, :foo) { |i| i * i }
    }.should complain(/block supersedes default value argument/)
    @result.should == 81
  end

  it "raises an ArgumentError when not passed one or two arguments" do
    lambda { {}.fetch()        }.should raise_error(ArgumentError)
    lambda { {}.fetch(1, 2, 3) }.should raise_error(ArgumentError)
  end
end
