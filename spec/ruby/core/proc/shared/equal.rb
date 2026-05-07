require_relative '../../../spec_helper'
require_relative '../fixtures/common'

describe :proc_equal, shared: true do
  it "is a public method" do
    Proc.public_instance_methods(false).should.include?(@method)
  end

  it "returns true if self and other are the same object" do
    p = proc { :foo }
    p.send(@method, p).should == true

    p = Proc.new { :foo }
    p.send(@method, p).should == true

    p = -> { :foo }
    p.send(@method, p).should == true
  end

  it "returns true if other is a dup of the original" do
    p = proc { :foo }
    p.send(@method, p.dup).should == true

    p = Proc.new { :foo }
    p.send(@method, p.dup).should == true

    p = -> { :foo }
    p.send(@method, p.dup).should == true
  end

  # identical here means the same method invocation.
  it "returns false when bodies are the same but capture env is not identical" do
    a = ProcSpecs.proc_for_1
    b = ProcSpecs.proc_for_1

    a.send(@method, b).should == false
  end

  it "returns false if procs are distinct but have the same body and environment" do
    p = proc { :foo }
    p2 = proc { :foo }
    p.send(@method, p2).should == false
  end

  it "returns false if lambdas are distinct but have same body and environment" do
    x = -> { :foo }
    x2 = -> { :foo }
    x.send(@method, x2).should == false
  end

  it "returns false if using comparing lambda to proc, even with the same body and env" do
    p = -> { :foo }
    p2 = proc { :foo }
    p.send(@method, p2).should == false

    x = proc { :bar }
    x2 = -> { :bar }
    x.send(@method, x2).should == false
  end

  it "returns false if other is not a Proc" do
    p = proc { :foo }
    p.send(@method, []).should == false

    p = Proc.new { :foo }
    p.send(@method, Object.new).should == false

    p = -> { :foo }
    p.send(@method, :foo).should == false
  end

  it "returns false if self and other are both procs but have different bodies" do
    p = proc { :bar }
    p2 = proc { :foo }
    p.send(@method, p2).should == false
  end

  it "returns false if self and other are both lambdas but have different bodies" do
    p = -> { :foo }
    p2 = -> { :bar }
    p.send(@method, p2).should == false
  end
end
