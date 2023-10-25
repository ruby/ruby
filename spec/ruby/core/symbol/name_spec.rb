require_relative '../../spec_helper'

describe "Symbol#name" do
  it "returns string" do
    :ruby.name.should == "ruby"
    :ルビー.name.should == "ルビー"
  end

  it "returns same string instance" do
    :"ruby_3".name.should.equal?(:ruby_3.name)
    :"ruby_#{1+2}".name.should.equal?(:ruby_3.name)
  end

  it "returns frozen string" do
    :symbol.name.should.frozen?
  end
end
