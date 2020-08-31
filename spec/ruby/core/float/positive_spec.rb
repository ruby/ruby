require_relative '../../spec_helper'

describe "Float#positive?" do
  describe "on positive numbers" do
    it "returns true" do
      0.1.positive?.should be_true
    end
  end

  describe "on zero" do
    it "returns false" do
      0.0.positive?.should be_false
    end
  end

  describe "on negative zero" do
    it "returns false" do
      -0.0.positive?.should be_false
    end
  end

  describe "on negative numbers" do
    it "returns false" do
      -0.1.positive?.should be_false
    end
  end

  describe "on NaN" do
    it "returns false" do
      nan_value.positive?.should be_false
    end
  end
end
