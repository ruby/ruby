require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../method/shared/aliased_inspect'

describe "UnboundMethod#to_s" do
  it_behaves_like :method_to_s_aliased, :to_s, -> meth { meth.unbind }

  before :each do
    @from_module = UnboundMethodSpecs::Methods.instance_method(:from_mod)
    @from_method = UnboundMethodSpecs::Methods.new.method(:from_mod).unbind
  end

  it "returns a String" do
    @from_module.to_s.should.is_a?(String)
    @from_method.to_s.should.is_a?(String)
  end

  it "the String reflects that this is an UnboundMethod object" do
    @from_module.to_s.should =~ /\bUnboundMethod\b/
    @from_method.to_s.should =~ /\bUnboundMethod\b/
  end

  it "the String shows the method name, Module defined in and Module extracted from" do
    @from_module.to_s.should =~ /\bfrom_mod\b/
    @from_module.to_s.should =~ /\bUnboundMethodSpecs::Mod\b/
  end

  it "returns a String including all details" do
    @from_module.to_s.should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Mod#from_mod"
    @from_method.to_s.should.start_with? "#<UnboundMethod: UnboundMethodSpecs::Mod#from_mod"
  end

  it "does not show the defining module if it is the same as the origin" do
    UnboundMethodSpecs::A.instance_method(:baz).to_s.should.start_with? "#<UnboundMethod: UnboundMethodSpecs::A#baz"
  end
end
