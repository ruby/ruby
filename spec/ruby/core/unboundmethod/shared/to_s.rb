require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :unboundmethod_to_s, shared: true do
  before :each do
    @from_module = UnboundMethodSpecs::Methods.instance_method(:from_mod)
    @from_method = UnboundMethodSpecs::Methods.new.method(:from_mod).unbind
  end

  it "returns a String" do
    @from_module.send(@method).should be_kind_of(String)
    @from_method.send(@method).should be_kind_of(String)
  end

  it "the String reflects that this is an UnboundMethod object" do
    @from_module.send(@method).should =~ /\bUnboundMethod\b/
    @from_method.send(@method).should =~ /\bUnboundMethod\b/
  end

  it "the String shows the method name, Module defined in and Module extracted from" do
    @from_module.send(@method).should =~ /\bfrom_mod\b/
    @from_module.send(@method).should =~ /\bUnboundMethodSpecs::Mod\b/

    ruby_version_is ""..."3.2" do
      @from_method.send(@method).should =~ /\bUnboundMethodSpecs::Methods\b/
    end
  end

  it "returns a String including all details" do
    ruby_version_is ""..."3.2" do
      @from_module.send(@method).should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Methods(UnboundMethodSpecs::Mod)#from_mod"
      @from_method.send(@method).should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Methods(UnboundMethodSpecs::Mod)#from_mod"
    end

    ruby_version_is "3.2" do
      @from_module.send(@method).should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Mod#from_mod"
      @from_method.send(@method).should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Mod#from_mod"
    end
  end

  it "does not show the defining module if it is the same as the origin" do
    UnboundMethodSpecs::A.instance_method(:baz).send(@method).should.start_with? "#<UnboundMethod: UnboundMethodSpecs::A#baz"
  end
end
