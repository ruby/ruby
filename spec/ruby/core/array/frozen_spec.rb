require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Array#frozen?" do
  it "returns true if array is frozen" do
    a = [1, 2, 3]
    a.should_not.frozen?
    a.freeze
    a.should.frozen?
  end

  it "returns false for an array being sorted by #sort" do
    a = [1, 2, 3]
    a.sort { |x,y| a.should_not.frozen?; x <=> y }
  end
end
