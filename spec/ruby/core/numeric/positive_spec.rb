require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#positive?" do
  describe "on positive numbers" do
    it "returns true" do
      1.positive?.should be_true
      0.1.positive?.should be_true
    end
  end

  describe "on zero" do
    it "returns false" do
      0.positive?.should be_false
      0.0.positive?.should be_false
    end
  end

  describe "on negative numbers" do
    it "returns false" do
      -1.positive?.should be_false
      -0.1.positive?.should be_false
    end
  end
end

describe "Numeric#positive?" do
  before(:each) do
    @obj = NumericSpecs::Subclass.new
  end

  it "returns true if self is greater than 0" do
    @obj.should_receive(:>).with(0).and_return(true)
    @obj.should.positive?
  end

  it "returns false if self is less than 0" do
    @obj.should_receive(:>).with(0).and_return(false)
    @obj.should_not.positive?
  end
end
