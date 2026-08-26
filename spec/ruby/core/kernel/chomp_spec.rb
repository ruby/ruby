# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#chomp" do
  it "is a private method only when -n is passed" do
    Kernel.private_instance_methods(false).should_not.include?(:chomp)
    KernelSpecs.private_instance_method_with_dash_n?(:chomp).should == true
  end

  it "removes the final newline of $_" do
    KernelSpecs.chomp_with_dash_n("abc\n").should == "abc"
  end

  it "removes the final carriage return of $_" do
    KernelSpecs.chomp_with_dash_n("abc\r").should == "abc"
  end

  it "removes the final carriage return, newline of $_" do
    KernelSpecs.chomp_with_dash_n("abc\r\n").should == "abc"
  end

  it "removes only the final newline of $_" do
    KernelSpecs.chomp_with_dash_n("abc\n\n").should == "abc\n"
  end

  it "removes the value of $/ from the end of $_" do
    KernelSpecs.chomp_with_dash_n("abcde", "cde").should == "ab"
  end
end

describe "Kernel#chomp" do
  before :each do
    @external = Encoding.default_external
    Encoding.default_external = Encoding::UTF_8
  end

  after :each do
    Encoding.default_external = @external
  end

  it "removes the final carriage return, newline from a multi-byte $_" do
    script = fixture __FILE__, "chomp.rb"
    KernelSpecs.run_with_dash_n(script).should == "あれ"
  end
end

describe "Kernel.chomp" do
  it "is a public method only when -n is passed" do
    Kernel.public_methods(false).should_not.include?(:chomp)
    KernelSpecs.public_singleton_method_with_dash_n?(:chomp).should == true
  end
end
