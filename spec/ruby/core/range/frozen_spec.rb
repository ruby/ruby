require_relative '../../spec_helper'

# There is no Range#frozen? method but this feels like the best place for these specs
describe "Range#frozen?" do
  it "is true for literal ranges" do
    (1..2).should.frozen?
    (1..).should.frozen?
    (..1).should.frozen?
  end

  it "is true for Range.new" do
    Range.new(1, 2).should.frozen?
    Range.new(1, nil).should.frozen?
    Range.new(nil, 1).should.frozen?
  end

  it "is false for instances of a subclass of Range" do
    sub_range = Class.new(Range).new(1, 2)
    sub_range.should_not.frozen?
  end

  it "is false for Range.allocate" do
    Range.allocate.should_not.frozen?
  end
end
