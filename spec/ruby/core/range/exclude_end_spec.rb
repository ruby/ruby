require_relative '../../spec_helper'

describe "Range#exclude_end?" do
  it "returns false if the range does not exclude the end value" do
    (-2..2).should_not.exclude_end?
    ('A'..'B').should_not.exclude_end?
    (0.5..2.4).should_not.exclude_end?
    (0xfffd..0xffff).should_not.exclude_end?
    Range.new(0, 1).should_not.exclude_end?
  end

  it "returns true if the range excludes the end value" do
    (0...5).should.exclude_end?
    ('A'...'B').should.exclude_end?
    (0.5...2.4).should.exclude_end?
    (0xfffd...0xffff).should.exclude_end?
    Range.new(0, 1, true).should.exclude_end?
  end
end
