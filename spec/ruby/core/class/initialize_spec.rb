require_relative '../../spec_helper'

ruby_version_is ""..."4.1" do
  describe "Class#initialize" do
    it "is private" do
      Class.private_methods(false).should.include?(:initialize)
    end

    it "raises a TypeError when called on already initialized classes" do
      ->{
        Integer.send :initialize
      }.should.raise(TypeError)

      ->{
        Object.send :initialize
      }.should.raise(TypeError)
    end

    # See [redmine:2601]
    it "raises a TypeError when called on BasicObject" do
      ->{
        BasicObject.send :initialize
      }.should.raise(TypeError)
    end

    describe "when given the Class" do
      before :each do
        @uninitialized = Class.allocate
      end

      it "raises a TypeError" do
        ->{@uninitialized.send(:initialize, Class)}.should.raise(TypeError)
      end
    end
  end
end

ruby_version_is "4.1" do
  describe "Class#initialize" do
    it "is not defined" do
      Class.private_instance_methods(false).should_not.include?(:initialize)
      Class.instance_methods(false).should_not.include?(:initialize)
    end
  end
end
