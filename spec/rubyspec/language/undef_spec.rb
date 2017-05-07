require File.expand_path('../../spec_helper', __FILE__)

describe "The undef keyword" do
  it "undefines a method" do
    undef_class = Class.new do
      def meth(o); o; end
    end
    obj = undef_class.new
    obj.meth(5).should == 5
    undef_class.class_eval do
      undef meth
    end
    lambda { obj.meth(5) }.should raise_error(NoMethodError)
  end

  it "allows undefining multiple methods at a time" do
    undef_multiple = Class.new do
      def method1; end
      def method2; :nope; end

      undef :method1, :method2
    end

    obj = undef_multiple.new
    obj.respond_to?(:method1).should == false
    obj.respond_to?(:method2).should == false
  end

  it "raises a NameError when passed a missing name" do
    Class.new do
      lambda {
         undef not_exist
      }.should raise_error(NameError) { |e|
        # a NameError and not a NoMethodError
        e.class.should == NameError
      }
    end
  end
end
