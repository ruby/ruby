require_relative '../../spec_helper'

describe "Float#negative?" do
  describe "on positive numbers" do
    it "returns false" do
      0.1.negative?.should be_false
    end
  end

  describe "on zero" do
    it "returns false" do
      0.0.negative?.should be_false
    end
  end

  describe "on negative zero" do
    it "returns false" do
      -0.0.negative?.should be_false
    end
  end

  describe "on negative numbers" do
    it "returns true" do
      -0.1.negative?.should be_true
    end
  end

  describe "on NaN" do
    it "returns false" do
      nan_value.negative?.should be_false
    end
  end
end
