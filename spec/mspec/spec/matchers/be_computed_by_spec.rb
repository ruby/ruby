require 'spec_helper'
require 'mspec/matchers'

RSpec.describe BeComputedByMatcher do
  it "matches when all entries in the Array compute" do
    array = [ [65, "A"],
              [90, "Z"] ]
    expect(BeComputedByMatcher.new(:chr).matches?(array)).to be_truthy
  end

  it "matches when all entries in the Array with arguments compute" do
    array = [ [1, 2, 3],
              [2, 4, 6] ]
    expect(BeComputedByMatcher.new(:+).matches?(array)).to be_truthy
  end

  it "does not match when any entry in the Array does not compute" do
    array = [ [65, "A" ],
              [91, "Z" ] ]
    expect(BeComputedByMatcher.new(:chr).matches?(array)).to be_falsey
  end

  it "accepts an argument list to apply to each method call" do
    array = [ [65, "1000001" ],
              [90, "1011010" ] ]
    expect(BeComputedByMatcher.new(:to_s, 2).matches?(array)).to be_truthy
  end

  it "does not match when any entry in the Array with arguments does not compute" do
    array = [ [1, 2, 3],
              [2, 4, 7] ]
    expect(BeComputedByMatcher.new(:+).matches?(array)).to be_falsey
  end

  it "provides a useful failure message" do
    array = [ [65, "A" ],
              [91, "Z" ] ]
    matcher = BeComputedByMatcher.new(:chr)
    matcher.matches?(array)
    expect(matcher.failure_message).to eq(["Expected \"Z\"", "to be computed by 91.chr (computed \"[\" instead)"])
  end
end
