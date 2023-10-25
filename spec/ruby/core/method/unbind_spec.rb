require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#unbind" do
  before :each do
    @normal = MethodSpecs::Methods.new
    @normal_m = @normal.method :foo
    @normal_um = @normal_m.unbind
    @pop_um = MethodSpecs::MySub.new.method(:bar).unbind
    @string = @pop_um.inspect.sub(/0x\w+/, '0xXXXXXX')
  end

  it "returns an UnboundMethod" do
    @normal_um.should be_kind_of(UnboundMethod)
  end

  describe "#inspect" do
    it "returns a String containing 'UnboundMethod'" do
      @string.should =~ /\bUnboundMethod\b/
    end

    it "returns a String containing the method name" do
      @string.should =~ /\#bar/
    end

    it "returns a String containing the Module the method is defined in" do
      @string.should =~ /MethodSpecs::MyMod/
    end

    ruby_version_is ""..."3.2" do
      it "returns a String containing the Module the method is referenced from" do
        @string.should =~ /MethodSpecs::MySub/
      end
    end

    ruby_version_is "3.2" do
      it "returns a String containing the Module the method is referenced from" do
        @string.should =~ /MethodSpecs::MyMod/
      end
    end
  end

  it "keeps the origin singleton class if there is one" do
    obj = Object.new
    def obj.foo
    end
    obj.method(:foo).unbind.inspect.should.start_with?("#<UnboundMethod: #{obj.singleton_class}#foo")
  end

  specify "rebinding UnboundMethod to Method's obj produces exactly equivalent Methods" do
    @normal_um.bind(@normal).should == @normal_m
    @normal_m.should == @normal_um.bind(@normal)
  end
end
