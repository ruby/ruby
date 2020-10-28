require_relative '../../../spec_helper'
require_relative '../fixtures/common'

describe :proc_equal, shared: true do
  it "is a public method" do
    Proc.should have_public_instance_method(@method, false)
  end

  it "returns true if self and other are the same object" do
    p = proc { :foo }
    p.send(@method, p).should be_true

    p = Proc.new { :foo }
    p.send(@method, p).should be_true

    p = -> { :foo }
    p.send(@method, p).should be_true
  end

  it "returns true if other is a dup of the original" do
    p = proc { :foo }
    p.send(@method, p.dup).should be_true

    p = Proc.new { :foo }
    p.send(@method, p.dup).should be_true

    p = -> { :foo }
    p.send(@method, p.dup).should be_true
  end

  # identical here means the same method invocation.
  it "returns false when bodies are the same but capture env is not identical" do
    a = ProcSpecs.proc_for_1
    b = ProcSpecs.proc_for_1

    a.send(@method, b).should be_false
  end

  it "returns false if procs are distinct but have the same body and environment" do
    p = proc { :foo }
    p2 = proc { :foo }
    p.send(@method, p2).should be_false
  end

  it "returns false if lambdas are distinct but have same body and environment" do
    x = -> { :foo }
    x2 = -> { :foo }
    x.send(@method, x2).should be_false
  end

  it "returns false if using comparing lambda to proc, even with the same body and env" do
    p = -> { :foo }
    p2 = proc { :foo }
    p.send(@method, p2).should be_false

    x = proc { :bar }
    x2 = -> { :bar }
    x.send(@method, x2).should be_false
  end

  it "returns false if other is not a Proc" do
    p = proc { :foo }
    p.send(@method, []).should be_false

    p = Proc.new { :foo }
    p.send(@method, Object.new).should be_false

    p = -> { :foo }
    p.send(@method, :foo).should be_false
  end

  it "returns false if self and other are both procs but have different bodies" do
    p = proc { :bar }
    p2 = proc { :foo }
    p.send(@method, p2).should be_false
  end

  it "returns false if self and other are both lambdas but have different bodies" do
    p = -> { :foo }
    p2 = -> { :bar }
    p.send(@method, p2).should be_false
  end
end

describe :proc_equal_undefined, shared: true do
  it "is not defined" do
    Proc.should_not have_instance_method(@method, false)
  end

  it "returns false if other is a dup of the original" do
    p = proc { :foo }
    p.send(@method, p.dup).should be_false

    p = Proc.new { :foo }
    p.send(@method, p.dup).should be_false

    p = -> { :foo }
    p.send(@method, p.dup).should be_false
  end
end
