require_relative '../spec_helper'
require_relative 'fixtures/classes'

describe "Literal Ranges" do
  it "creates range object" do
    (1..10).should == Range.new(1, 10)
  end

  it "creates range with excluded right boundary" do
    (1...10).should == Range.new(1, 10, true)
  end

  it "creates endless ranges" do
    (1..).should == Range.new(1, nil)
    (1...).should == Range.new(1, nil, true)
  end

  ruby_version_is "3.0" do
    it "is frozen" do
      (42..).should.frozen?
    end
  end

  ruby_version_is "2.7" do
    it "creates beginless ranges" do
      eval("(..1)").should == Range.new(nil, 1)
      eval("(...1)").should == Range.new(nil, 1, true)
    end
  end
end
