require_relative '../../spec_helper'

describe "Module#singleton_class?" do
  it "returns true for singleton classes" do
    xs = self.singleton_class
    xs.should.singleton_class?
  end

  it "returns false for other classes" do
    c = Class.new
    c.should_not.singleton_class?
  end

  describe "with singleton values" do
    it "returns false for nil's singleton class" do
      NilClass.should_not.singleton_class?
    end

    it "returns false for true's singleton class" do
      TrueClass.should_not.singleton_class?
    end

    it "returns false for false's singleton class" do
      FalseClass.should_not.singleton_class?
    end
  end
end
