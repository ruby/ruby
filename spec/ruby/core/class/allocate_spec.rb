require_relative '../../spec_helper'

describe "Class#allocate" do
  it "returns an instance of self" do
    klass = Class.new
    klass.allocate.should.instance_of?(klass)
  end

  it "does not call initialize on the new instance" do
    klass = Class.new do
      def initialize(*args)
        @initialized = true
      end

      def initialized?
        @initialized || false
      end
    end

    klass.allocate.should_not.initialized?
  end

  ruby_version_is ""..."4.1" do
    it "returns a fully-formed instance of Module" do
      klass = Class.allocate
      klass.constants.should_not == nil
      klass.methods.should_not == nil
    end

    it "throws an exception when calling a method on a new instance" do
      klass = Class.allocate
      -> do
        klass.new
      end.should.raise(Exception)
    end

    it "raises TypeError for #superclass" do
      -> do
        Class.allocate.superclass
      end.should.raise(TypeError)
    end
  end

  ruby_version_is "4.1" do
    it "raises NoMethodError when called on Class itself" do
      -> { Class.allocate }.should.raise(NoMethodError)
    end
  end
end
