require_relative '../spec_helper'
require_relative 'fixtures/classes'

describe "Literal Ranges" do
  it "creates range object" do
    (1..10).should == Range.new(1, 10)
  end

  it "creates range with excluded right boundary" do
    (1...10).should == Range.new(1, 10, true)
  end

  ruby_version_is "2.6" do
    it "creates endless ranges" do
      eval("(1..)").should == Range.new(1, nil)
      eval("(1...)").should == Range.new(1, nil, true)
    end
  end
end
