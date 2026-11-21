require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe "SimpleDelegator.new" do
  before :all do
    @simple = DelegateSpecs::Simple.new
    @delegate = SimpleDelegator.new(@simple)
  end

  it "forwards public method calls" do
    @delegate.pub.should == :foo
  end

  it "forwards protected method calls" do
    ->{ @delegate.prot }.should.raise( NoMethodError )
  end

  it "doesn't forward private method calls" do
    ->{ @delegate.priv }.should.raise( NoMethodError )
  end

  it "doesn't forward private method calls even via send or __send__" do
    ->{ @delegate.send(:priv, 42)     }.should.raise( NoMethodError )
    ->{ @delegate.__send__(:priv, 42) }.should.raise( NoMethodError )
  end
end
