require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct#to_h" do
  before :each do
    @h = {name: "John Smith", age: 70, pension: 300}
    @os = OpenStruct.new(@h)
    @to_h = @os.to_h
  end

  it "returns a Hash with members as keys" do
    @to_h.should == @h
  end

  it "returns a Hash with keys as symbols" do
    os = OpenStruct.new("name" => "John Smith", "age" => 70)
    os.pension = 300
    os.to_h.should == @h
  end

  it "does not return the hash used as initializer" do
    @to_h.should_not equal(@h)
  end

  it "returns a Hash that is independent from the struct" do
    @to_h[:age] = 71
    @os.age.should == 70
  end

  ruby_version_is "2.6" do
    it "converts [key, value] pairs returned by the block to a hash" do
      h = @os.to_h {|key, value| [key.to_s, value * 2]}
      h.should == {"name" => "John SmithJohn Smith", "age" => 140, "pension" => 600}
    end
  end
end
