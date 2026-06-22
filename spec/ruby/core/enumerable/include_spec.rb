require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Enumerable#include?" do
  it "returns true if any element == argument for numbers" do
    class EnumerableSpecIncludeP; def ==(obj) obj == 5; end; end

    elements = (0..5).to_a
    EnumerableSpecs::Numerous.new(*elements).include?(5).should == true
    EnumerableSpecs::Numerous.new(*elements).include?(10).should == false
    EnumerableSpecs::Numerous.new(*elements).include?(EnumerableSpecIncludeP.new).should == true
  end

  it "returns true if any element == argument for other objects" do
    class EnumerableSpecIncludeP11; def ==(obj); obj == '11'; end; end

    elements = ('0'..'5').to_a + [EnumerableSpecIncludeP11.new]
    EnumerableSpecs::Numerous.new(*elements).include?('5').should == true
    EnumerableSpecs::Numerous.new(*elements).include?('10').should == false
    EnumerableSpecs::Numerous.new(*elements).include?(EnumerableSpecIncludeP11.new).should == true
    EnumerableSpecs::Numerous.new(*elements).include?('11').should == true
  end


  it "returns true if any member of enum equals obj when == compare different classes (legacy rubycon)" do
    # equality is tested with ==
    EnumerableSpecs::Numerous.new(2,4,6,8,10).include?(2.0).should == true
    EnumerableSpecs::Numerous.new(2,4,[6,8],10).include?([6, 8]).should == true
    EnumerableSpecs::Numerous.new(2,4,[6,8],10).include?([6.0, 8.0]).should == true
  end

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.include?([1,2]).should == true
  end
end
