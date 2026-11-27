require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.memsize_of" do
  it "returns 0 for true, false and nil" do
    ObjectSpace.memsize_of(true).should == 0
    ObjectSpace.memsize_of(false).should == 0
    ObjectSpace.memsize_of(nil).should == 0
  end

  it "returns 0 for small Integers" do
    ObjectSpace.memsize_of(42).should == 0
  end

  it "returns 0 for literal Symbols" do
    ObjectSpace.memsize_of(:object_space_memsize_spec_static_sym).should == 0
  end

  it "returns a positive Integer for an Object" do
    obj = Object.new
    ObjectSpace.memsize_of(obj).should.is_a?(Integer)
    ObjectSpace.memsize_of(obj).should > 0
  end

  it "is larger if the Object has more instance variables" do
    before = ObjectSpace.memsize_of(Object.new)

    klass = Class.new do
      set_ivar = 100.times.map { |i| "@foo#{i} = nil" }
      class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
        def initialize
          #{set_ivar.join("; ")}
        end
      RUBY
    end

    klass.new # in case the runtime needs warmup

    after = ObjectSpace.memsize_of(klass.new)
    after.should > before
  end
end
