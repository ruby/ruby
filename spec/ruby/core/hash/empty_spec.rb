require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#empty?" do
  it "returns true if the hash has no entries" do
    {}.should.empty?
    { 1 => 1 }.should_not.empty?
  end

  it "returns true if the hash has no entries and has a default value" do
    Hash.new(5).should.empty?
    Hash.new { 5 }.should.empty?
    Hash.new { |hsh, k| hsh[k] = k }.should.empty?
  end
end
