require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :method_to_s, shared: true do
  before :each do
    @m = MethodSpecs::MySub.new.method :bar
    @string = @m.send(@method).sub(/0x\w+/, '0xXXXXXX')
  end

  it "returns a String" do
    @m.send(@method).should be_kind_of(String)
  end

  it "returns a String for methods defined with attr_accessor" do
    m = MethodSpecs::Methods.new.method :attr
    m.send(@method).should be_kind_of(String)
  end

  it "returns a String containing 'Method'" do
    @string.should =~ /\bMethod\b/
  end

  it "returns a String containing the method name" do
    @string.should =~ /\#bar/
  end

  it "returns a String containing the Module the method is defined in" do
    @string.should =~ /MethodSpecs::MyMod/
  end

  it "returns a String containing the Module the method is referenced from" do
    @string.should =~ /MethodSpecs::MySub/
  end

  ruby_version_is '2.8' do
    it "returns a String containing the Module containing the method if object has a singleton class but method is not defined in the singleton class" do
      obj = MethodSpecs::MySub.new
      obj.singleton_class
      @m = obj.method(:bar)
      @string = @m.send(@method).sub(/0x\w+/, '0xXXXXXX')
      @string.should =~ /\A#<Method: MethodSpecs::MySub\(MethodSpecs::MyMod\)#bar\(\) /
    end
  end

  it "returns a String containing the singleton class if method is defined in the singleton class" do
    obj = MethodSpecs::MySub.new
    def obj.bar; end
    @m = obj.method(:bar)
    @string = @m.send(@method).sub(/0x\w+/, '0xXXXXXX')
    @string.should =~ /\A#<Method: #<MethodSpecs::MySub:0xXXXXXX>\.bar/
  end
end
