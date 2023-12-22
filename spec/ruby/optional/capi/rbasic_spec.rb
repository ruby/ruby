require_relative 'spec_helper'
require_relative 'shared/rbasic'
load_extension("rbasic")
load_extension("data")
load_extension("array")

describe "RBasic support for regular objects" do
  before :all do
    @specs = CApiRBasicSpecs.new
    @data = -> { [Object.new, Object.new] }
  end
  it_should_behave_like :rbasic
end

describe "RBasic support for RData" do
  before :all do
    @specs = CApiRBasicRDataSpecs.new
    @wrapping = CApiWrappedStructSpecs.new
    @data = -> { [@wrapping.wrap_struct(1024), @wrapping.wrap_struct(1025)] }
  end
  it_should_behave_like :rbasic

  it "supports user flags" do
    obj, _ = @data.call
    initial = @specs.get_flags(obj)
    @specs.set_flags(obj, 1 << 14 | 1 << 16 | initial).should == 1 << 14 | 1 << 16 | initial
    @specs.get_flags(obj).should == 1 << 14 | 1 << 16 | initial
    @specs.set_flags(obj, initial).should == initial
  end

  it "supports copying the flags from one object over to the other" do
    obj1, obj2 = @data.call
    initial = @specs.get_flags(obj1)
    @specs.get_flags(obj2).should == initial
    @specs.set_flags(obj1, 1 << 14 | 1 << 16 | initial)
    @specs.get_flags(obj1).should == 1 << 14 | 1 << 16 | initial

    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == 1 << 14 | 1 << 16 | initial
    @specs.set_flags(obj1, initial)
    @specs.copy_flags(obj2, obj1)
    @specs.get_flags(obj2).should == initial
  end
end
