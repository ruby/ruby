# -*- encoding: us-ascii -*-

require_relative '../../spec_helper'

describe "Module#prepended" do
  before :each do
    ScratchPad.clear
  end

  it "is a private method" do
    Module.private_instance_methods(false).should.include?(:prepended)
  end

  it "is invoked when self is prepended to another module or class" do
    m = Module.new do
      def self.prepended(o)
        ScratchPad.record o
      end
    end

    c = Class.new { prepend m }

    ScratchPad.recorded.should == c
  end
end
