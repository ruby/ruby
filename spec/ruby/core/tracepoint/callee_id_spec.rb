require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)

ruby_version_is '2.4' do
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
end

