require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#append_features" do
  it "is a private method" do
    Module.private_instance_methods(false).should.include?(:append_features)
  end

  describe "on Class" do
    it "is undefined" do
      Class.private_instance_methods(true).should_not.include?(:append_features)
    end

    it "raises a TypeError if calling after rebinded to Class" do
      -> {
        Module.instance_method(:append_features).bind(Class.new).call Module.new
      }.should.raise(TypeError)
    end
  end

  it "gets called when self is included in another module/class" do
    begin
      m = Module.new do
        def self.append_features(mod)
          $appended_to = mod
        end
      end

      c = Class.new do
        include m
      end

      $appended_to.should == c
    ensure
      $appended_to = nil
    end
  end

  it "raises an ArgumentError on a cyclic include" do
    -> {
      ModuleSpecs::CyclicAppendA.send(:append_features, ModuleSpecs::CyclicAppendA)
    }.should.raise(ArgumentError)

    -> {
      ModuleSpecs::CyclicAppendB.send(:append_features, ModuleSpecs::CyclicAppendA)
    }.should.raise(ArgumentError)

  end

  describe "when other is frozen" do
    before :each do
      @receiver = Module.new
      @other = Module.new.freeze
    end

    it "raises a FrozenError before appending self" do
      -> { @receiver.send(:append_features, @other) }.should.raise(FrozenError)
      @other.ancestors.should_not.include?(@receiver)
    end
  end
end
