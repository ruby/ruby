# truffleruby_primitives: true
require_relative '../../spec_helper'

describe "Kernel#singleton_class" do
  it "returns class extended from an object" do
    x = Object.new
    xs = class << x; self; end
    xs.should == x.singleton_class
  end

  it "returns NilClass for nil" do
    nil.singleton_class.should == NilClass
  end

  it "returns TrueClass for true" do
    true.singleton_class.should == TrueClass
  end

  it "returns FalseClass for false" do
    false.singleton_class.should == FalseClass
  end

  it "raises TypeError for Integer" do
    -> { 123.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for Float" do
    -> { 3.14.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for Symbol" do
    -> { :foo.singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "raises TypeError for a frozen deduplicated String" do
    -> { (-"string").singleton_class }.should raise_error(TypeError, "can't define singleton")
    -> { a = -"string"; a.singleton_class }.should raise_error(TypeError, "can't define singleton")
    -> { a = "string"; (-a).singleton_class }.should raise_error(TypeError, "can't define singleton")
  end

  it "returns a frozen singleton class if object is frozen" do
    obj = Object.new
    obj.freeze
    obj.singleton_class.frozen?.should be_true
  end

  context "for an IO object with a replaced singleton class" do
    it "looks up singleton methods from the fresh singleton class after an object instance got a new one" do
      proxy = -> io { io.foo }
      if RUBY_ENGINE == 'truffleruby'
        # We need an inline cache with only this object seen, the best way to do that is to use a Primitive
        sclass = -> io { Primitive.singleton_class(io) }
      else
        sclass = -> io { io.singleton_class }
      end

      io = File.new(__FILE__)
      io.define_singleton_method(:foo) { "old" }
      sclass1 = sclass.call(io)
      proxy.call(io).should == "old"

      # IO#reopen is the only method which can replace an object's singleton class
      io2 = File.new(__FILE__)
      io.reopen(io2)
      io.define_singleton_method(:foo) { "new" }
      sclass2 = sclass.call(io)
      sclass2.should_not.equal?(sclass1)
      proxy.call(io).should == "new"
    ensure
      io2.close
      io.close
    end
  end
end
