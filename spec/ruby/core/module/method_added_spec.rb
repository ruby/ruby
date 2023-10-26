require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Module#method_added" do
  before :each do
    ScratchPad.record []
  end

  it "is a private instance method" do
    Module.should have_private_instance_method(:method_added)
  end

  it "returns nil in the default implementation" do
    Module.new do
      method_added(:test).should == nil
    end
  end

  it "is called when a new instance method is defined in self" do
    Module.new do
      def self.method_added(name)
        ScratchPad << name
      end

      def test() end
      def test2() end
      def test() end
      alias_method :aliased_test, :test
      alias aliased_test2 test
    end

    ScratchPad.recorded.should == [:test, :test2, :test, :aliased_test, :aliased_test2]
  end

  it "is not called when a singleton method is added" do
    # obj.singleton_method_added is called instead
    klass = Class.new
    def klass.method_added(name)
      ScratchPad << name
    end

    obj = klass.new
    def obj.new_singleton_method
    end

    ScratchPad.recorded.should == []
  end

  it "is not called when a method is undefined in self" do
    m = Module.new do
      def method_to_undef
      end

      def self.method_added(name)
        fail("method_added called by undef_method")
      end

      undef_method :method_to_undef
    end
    m.should_not have_method(:method_to_undef)
  end

  it "is not called when a method changes visibility" do
    Module.new do
      def public_method
      end

      def private_method
      end

      def self.method_added(name)
        ScratchPad << name
      end

      public :public_method
      private :public_method

      private :private_method
      public :private_method
    end

    ScratchPad.recorded.should == []
  end

  it "is called when using #private in a subclass" do
    parent = Class.new do
      def foo
      end
    end

    Class.new(parent) do
      def self.method_added(name)
        ScratchPad << name
      end

      # Create an instance as that might initialize some method lookup caches, which is interesting to test
      self.new.foo

      private :foo
      public :foo
    end

    ScratchPad.recorded.should == [:foo]
  end

  it "is not called when a method is copied via module_function, rather #singleton_method_added is called" do
    Module.new do
      def mod_function
      end

      def self.method_added(name)
        ScratchPad << [:method_added, name]
      end

      def self.singleton_method_added(name)
        ScratchPad << [:singleton_method_added, name]
      end

      ScratchPad.record []

      module_function :mod_function
    end

    ScratchPad.recorded.should == [[:singleton_method_added, :mod_function]]
  end

  it "is called with a precise caller location with the line of the 'def'" do
    line = nil

    Module.new do
      def self.method_added(name)
        location = caller_locations(1, 1)[0]
        ScratchPad << location.lineno
      end

      line = __LINE__
      def first
      end

      def second
      end
    end

    ScratchPad.recorded.should == [line + 1, line + 4]
  end
end
