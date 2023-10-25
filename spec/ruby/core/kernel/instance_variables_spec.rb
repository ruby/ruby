require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#instance_variables" do
  describe "immediate values" do
    it "returns an empty array if no instance variables are defined" do
      [0, 0.5, true, false, nil].each do |value|
        value.instance_variables.should == []
      end
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

    it "returns the instances variables in the order declared" do
      c = Class.new do
        def initialize
          @c = 1
          @a = 2
          @b = 3
        end
      end
      c.new.instance_variables.should == [:@c, :@a, :@b]
    end
  end
end
