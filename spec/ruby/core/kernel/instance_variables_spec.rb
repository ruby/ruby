require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#instance_variables" do
  describe "immediate values" do
    it "returns an empty array if no instance variables are defined" do
      0.instance_variables.should == []
    end

    it "returns the correct array if an instance variable is added" do
      a = 0
      ->{ a.instance_variable_set("@test", 1) }.should raise_error(RuntimeError)
    end
  end

  describe "regular objects" do
    it "returns an empty array if no instance variables are defined" do
      Object.new.instance_variables.should == []
    end

    it "returns the correct array if an instance variable is added" do
      a = Object.new
      a.instance_variable_set("@test", 1)
      a.instance_variables.should == [:@test]
    end
  end
end
