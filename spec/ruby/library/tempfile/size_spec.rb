require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile#size" do
  before :each do
    @tempfile = Tempfile.new("specs")
  end

  after :each do
    @tempfile.close!
  end

  it "returns the size of self" do
    @tempfile.size.should.eql?(0)
    @tempfile.print("Test!")
    @tempfile.size.should.eql?(5)
  end

  it "returns the size of self even if self is closed" do
    @tempfile.print("Test!")
    @tempfile.close
    @tempfile.size.should.eql?(5)
  end
end
