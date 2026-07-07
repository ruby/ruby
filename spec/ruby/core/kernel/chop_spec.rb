# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#chop" do
  it "is a private method only when -n is passed" do
    Kernel.private_instance_methods(false).should_not.include?(:chop)
    KernelSpecs.private_instance_method_with_dash_n?(:chop).should == true
  end

  it "removes the final character of $_" do
    KernelSpecs.chop_with_dash_n("abc").should == "ab"
  end

  it "removes the final carriage return, newline of $_" do
    KernelSpecs.chop_with_dash_n("abc\r\n").should == "abc"
  end
end

describe "Kernel#chop" do
  before :each do
    @external = Encoding.default_external
    Encoding.default_external = Encoding::UTF_8
  end

  after :each do
    Encoding.default_external = @external
  end

  it "removes the final multi-byte character from $_" do
    script = fixture __FILE__, "chop.rb"
    KernelSpecs.run_with_dash_n(script).should == "あ"
  end
end

describe "Kernel.chop" do
  it "is a public method only when -n is passed" do
    Kernel.public_methods(false).should_not.include?(:chop)
    KernelSpecs.public_singleton_method_with_dash_n?(:chop).should == true
  end
end
