require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#original_name" do
  it "returns the name of the method" do
    String.instance_method(:upcase).original_name.should == :upcase
  end

  it "returns the original name" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:foo).unbind.original_name.should == :foo
    obj.method(:bar).unbind.original_name.should == :foo
    UnboundMethodSpecs::Methods.instance_method(:bar).original_name.should == :foo
  end

  it "returns the original name even when aliased twice" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:foo).unbind.original_name.should == :foo
    obj.method(:baz).unbind.original_name.should == :foo
    UnboundMethodSpecs::Methods.instance_method(:baz).original_name.should == :foo
  end

  it "returns the original name even when aliased thrice" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:qux).unbind.original_name.should == :foo
    UnboundMethodSpecs::Methods.instance_method(:qux).original_name.should == :foo
  end

  it "returns the source UnboundMethod's name (not the name given to define_method)" do
    klass = Class.new { define_method(:my_inspect, ::Kernel.instance_method(:inspect)) }
    klass.instance_method(:my_inspect).original_name.should == :inspect
  end

  it "preserves the source method's name through define_method and alias" do
    source = Class.new { def my_method; end }
    klass = Class.new(source) do
      define_method(:renamed, source.instance_method(:my_method))
      alias aliased renamed
    end
    klass.instance_method(:renamed).original_name.should == :my_method
    klass.instance_method(:aliased).original_name.should == :my_method
  end
end
