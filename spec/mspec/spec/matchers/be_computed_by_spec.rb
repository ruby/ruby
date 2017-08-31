require 'spec_helper'
require 'mspec/matchers'

describe BeComputedByMatcher do
  it "matches when all entries in the Array compute" do
    array = [ [65, "A"],
              [90, "Z"] ]
    BeComputedByMatcher.new(:chr).matches?(array).should be_true
  end

  it "matches when all entries in the Array with arguments compute" do
    array = [ [1, 2, 3],
              [2, 4, 6] ]
    BeComputedByMatcher.new(:+).matches?(array).should be_true
  end

  it "does not match when any entry in the Array does not compute" do
    array = [ [65, "A" ],
              [91, "Z" ] ]
    BeComputedByMatcher.new(:chr).matches?(array).should be_false
  end

  it "accepts an argument list to apply to each method call" do
    array = [ [65, "1000001" ],
              [90, "1011010" ] ]
    BeComputedByMatcher.new(:to_s, 2).matches?(array).should be_true
  end

  it "does not match when any entry in the Array with arguments does not compute" do
    array = [ [1, 2, 3],
              [2, 4, 7] ]
    BeComputedByMatcher.new(:+).matches?(array).should be_false
  end

  it "provides a useful failure message" do
    array = [ [65, "A" ],
              [91, "Z" ] ]
    matcher = BeComputedByMatcher.new(:chr)
    matcher.matches?(array)
    matcher.failure_message.should == ["Expected \"Z\"", "to be computed by 91.chr (computed \"[\" instead)"]
  end
end
