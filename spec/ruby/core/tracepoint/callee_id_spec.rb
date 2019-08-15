require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "TracePoint#callee_id" do
  it "returns the called name of the method being called" do
    a = []
    obj = TracePointSpec::ClassWithMethodAlias.new

    TracePoint.new(:call) do |tp|
      a << tp.callee_id
    end.enable do
      obj.m_alias
    end

    a.should == [:m_alias]
  end
end
