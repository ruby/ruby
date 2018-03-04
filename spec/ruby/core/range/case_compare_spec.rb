require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/cover'

describe "Range#===" do
  it "returns the result of calling #include? on self" do
    range = 0...10
    range.should_receive(:include?).with(2).and_return(:true)
    (range === 2).should == :true
  end
end
