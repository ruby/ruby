require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "DelegateClass.instance_method" do
  before :all do
    @klass = DelegateSpecs::DelegateClass
    @obj = @klass.new(DelegateSpecs::Simple.new)
  end

  it "returns a method object for public instance methods of the delegated class" do
    m = @klass.instance_method(:pub)
    m.should.instance_of?(UnboundMethod)
    m.bind(@obj).call.should == :foo
  end

  it "returns a method object for protected instance methods of the delegated class" do
    m = @klass.instance_method(:prot)
    m.should.instance_of?(UnboundMethod)
    m.bind(@obj).call.should == :protected
  end

  it "raises a NameError for a private instance methods of the delegated class" do
    -> {
      @klass.instance_method(:priv)
    }.should.raise(NameError)
  end

  it "returns a method object for public instance methods of the DelegateClass class" do
    m = @klass.instance_method(:extra)
    m.should.instance_of?(UnboundMethod)
    m.bind(@obj).call.should == :cheese
  end

  it "returns a method object for protected instance methods of the DelegateClass class" do
    m = @klass.instance_method(:extra_protected)
    m.should.instance_of?(UnboundMethod)
    m.bind(@obj).call.should == :baz
  end

  it "returns a method object for private instance methods of the DelegateClass class" do
    m = @klass.instance_method(:extra_private)
    m.should.instance_of?(UnboundMethod)
    m.bind(@obj).call.should == :bar
  end

  it "raises a NameError for an invalid method name" do
    -> {
      @klass.instance_method(:invalid_and_silly_method_name)
    }.should.raise(NameError)
  end

end
