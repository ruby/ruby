require_relative '../../spec_helper'

describe "Kernel#singleton_method" do
  it "finds a method defined on the singleton class" do
    obj = Object.new
    def obj.foo; end
    obj.singleton_method(:foo).should be_an_instance_of(Method)
  end

  it "returns a Method which can be called" do
    obj = Object.new
    def obj.foo; 42; end
    obj.singleton_method(:foo).call.should == 42
  end

  it "only looks at singleton methods and not at methods in the class" do
    klass = Class.new do
      def foo
        42
      end
    end
    obj = klass.new
    obj.foo.should == 42
    -> {
      obj.singleton_method(:foo)
    }.should raise_error(NameError) { |e|
      # a NameError and not a NoMethodError
      e.class.should == NameError
    }
  end

  it "raises a NameError if there is no such method" do
    obj = Object.new
    -> {
      obj.singleton_method(:not_existing)
    }.should raise_error(NameError) { |e|
      # a NameError and not a NoMethodError
      e.class.should == NameError
    }
  end

  ruby_bug "#20620", ""..."3.4" do
    it "finds a method defined in a module included in the singleton class" do
      m = Module.new do
        def foo
          :foo
        end
      end

      obj = Object.new
      obj.singleton_class.include(m)

      obj.singleton_method(:foo).should be_an_instance_of(Method)
      obj.singleton_method(:foo).call.should == :foo
    end

    it "finds a method defined in a module prepended in the singleton class" do
      m = Module.new do
        def foo
          :foo
        end
      end

      obj = Object.new
      obj.singleton_class.prepend(m)

      obj.singleton_method(:foo).should be_an_instance_of(Method)
      obj.singleton_method(:foo).call.should == :foo
    end

    it "finds a method defined in a module that an object is extended with" do
      m = Module.new do
        def foo
          :foo
        end
      end

      obj = Object.new
      obj.extend(m)

      obj.singleton_method(:foo).should be_an_instance_of(Method)
      obj.singleton_method(:foo).call.should == :foo
    end
  end
end
