require_relative '../../spec_helper'
require 'ostruct'

describe "OpenStruct.new when frozen" do
  before :each do
    @os = OpenStruct.new(name: "John Smith", age: 70, pension: 300).freeze
  end
  #
  # method_missing case handled in method_missing_spec.rb
  #
  it "is still readable" do
    @os.age.should eql(70)
    @os.pension.should eql(300)
    @os.name.should == "John Smith"
  end

  it "is not writable" do
    ->{ @os.age = 42 }.should raise_error( RuntimeError )
  end

  it "cannot create new fields" do
    ->{ @os.state = :new }.should raise_error( RuntimeError )
  end

  it "creates a frozen clone" do
    f = @os.clone
    f.frozen?.should == true
    f.age.should == 70
    ->{ f.age = 0 }.should raise_error( RuntimeError )
    ->{ f.state = :newer }.should raise_error( RuntimeError )
  end

  it "creates an unfrozen dup" do
    d = @os.dup
    d.frozen?.should == false
    d.age.should == 70
    d.age = 42
    d.age.should == 42
  end
end
