require_relative '../spec_helper'

describe "Safe navigator" do
  it "requires a method name to be provided" do
    -> { eval("obj&. {}") }.should raise_error(SyntaxError)
  end

  context "when context is nil" do
    it "always returns nil" do
      nil&.unknown.should == nil
      [][10]&.unknown.should == nil
    end

    it "can be chained" do
      nil&.one&.two&.three.should == nil
    end

    it "doesn't evaluate arguments" do
      obj = Object.new
      obj.should_not_receive(:m)
      nil&.unknown(obj.m) { obj.m }
    end
  end

  context "when context is false" do
    it "calls the method" do
      false&.to_s.should == "false"

      -> { false&.unknown }.should raise_error(NoMethodError)
    end
  end

  context "when context is truthy" do
    it "calls the method" do
      1&.to_s.should == "1"

      -> { 1&.unknown }.should raise_error(NoMethodError)
    end
  end

  it "takes a list of arguments" do
    [1,2,3]&.first(2).should == [1,2]
  end

  it "takes a block" do
    [1,2]&.map { |i| i * 2 }.should == [2, 4]
  end

  it "allows assignment methods" do
    klass = Class.new do
      attr_reader :foo
      def foo=(val)
        @foo = val
        42
      end
    end
    obj = klass.new

    (obj&.foo = 3).should == 3
    obj.foo.should == 3

    obj = nil
    (obj&.foo = 3).should == nil
  end

  it "allows assignment operators" do
    klass = Class.new do
      attr_reader :m

      def initialize
        @m = 0
      end

      def m=(v)
        @m = v
        42
      end
    end

    obj = klass.new

    obj&.m += 3
    obj.m.should == 3

    obj = nil
    (obj&.m += 3).should == nil
  end

  it "allows ||= operator" do
    klass = Class.new do
      attr_reader :m

      def initialize
        @m = false
      end

      def m=(v)
        @m = v
        42
      end
    end

    obj = klass.new

    (obj&.m ||= true).should == true
    obj.m.should == true

    obj = nil
    (obj&.m ||= true).should == nil
    obj.should == nil
  end

  it "allows &&= operator" do
    klass = Class.new do
      attr_accessor :m

      def initialize
        @m = true
      end
    end

    obj = klass.new

    (obj&.m &&= false).should == false
    obj.m.should == false

    obj = nil
    (obj&.m &&= false).should == nil
    obj.should == nil
  end

  it "does not call the operator method lazily with an assignment operator" do
    klass = Class.new do
      attr_writer :foo
      def foo
        nil
      end
    end
    obj = klass.new

    -> {
      obj&.foo += 3
    }.should raise_error(NoMethodError) { |e|
      e.name.should == :+
    }
  end
end
