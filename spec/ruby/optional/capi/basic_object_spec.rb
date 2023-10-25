require_relative 'spec_helper'

load_extension("basic_object")

describe "C-API basic object" do
  before :each do
    @s = CApiBasicObjectSpecs.new
  end

  describe "RBASIC_CLASS" do
    it "returns the class of an object" do
      c = Class.new
      o = c.new
      @s.RBASIC_CLASS(o).should == c
    end

    it "returns the singleton class" do
      o = Object.new
      @s.RBASIC_CLASS(o).should == Object
      singleton_class = o.singleton_class
      @s.RBASIC_CLASS(o).should == singleton_class
    end
  end
end
