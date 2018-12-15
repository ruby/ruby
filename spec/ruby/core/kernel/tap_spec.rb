require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#tap" do
  it "raises a LocalJumpError when no args or block is given" do
    lambda { 3.tap }.should raise_error(LocalJumpError)
  end

  it "returns self after yielding self when only a block is given" do
    a = KernelSpecs::A.new
    a.tap{|o| o.should equal(a); 42}.should equal(a)
  end

  ruby_version_is("2.6") do
    it "returns self after calling #send when any args are given" do
      a = [1, 2, 3]
      a.tap(:fetch, 1).should equal(a)

      a.tap(:delete, 1).should equal(a)
      a.should == [2, 3]

      a.tap(:tap) { |b| b.tap(:delete, 2) }.should equal(a)
      a.should == [3]

      lambda { a.tap(:missing) }.should raise_error(::NoMethodError)
    end
  end
end
