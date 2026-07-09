require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct#delete_field" do
  before :each do
    @os = OpenStruct.new(name: "John Smith", age: 70, pension: 300)
  end

  it "removes the named field from self's method/value table" do
    @os.delete_field(:name)
    @os[:name].should == nil
  end

  it "does remove the accessor methods" do
    @os.delete_field(:name)
    @os.respond_to?(:name).should == false
    @os.respond_to?(:name=).should == false
  end
end
