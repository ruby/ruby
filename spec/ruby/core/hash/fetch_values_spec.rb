require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/hash/key_error'

describe "Hash#fetch_values" do
  before :each do
    @hash = { a: 1, b: 2, c: 3 }
  end

  describe "with matched keys" do
    it "returns the values for keys" do
      @hash.fetch_values(:a).should == [1]
      @hash.fetch_values(:a, :c).should == [1, 3]
    end

    it "returns the values for keys ordered in the order of the requested keys" do
      @hash.fetch_values(:c, :a).should == [3, 1]
    end
  end

  describe "with unmatched keys" do
    it_behaves_like :key_error, -> obj, key { obj.fetch_values(key) }, Hash.new(a: 5)

    it "returns the default value from block" do
      @hash.fetch_values(:z) { |key| "`#{key}' is not found" }.should == ["`z' is not found"]
      @hash.fetch_values(:a, :z) { |key| "`#{key}' is not found" }.should == [1, "`z' is not found"]
    end
  end

  describe "without keys" do
    it "returns an empty Array" do
      @hash.fetch_values.should == []
    end
  end
end
