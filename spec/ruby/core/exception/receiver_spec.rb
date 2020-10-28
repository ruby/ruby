require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "NameError#receiver" do
  class ::ReceiverClass
    def call_undefined_class_variable; @@doesnt_exist end
  end

  it "returns the object that raised the exception" do
    receiver = Object.new

    -> {
      receiver.doesnt_exist
    }.should raise_error(NameError) {|e| e.receiver.should equal(receiver) }
  end

  it "returns the Object class when an undefined constant is called without namespace" do
    -> {
      DoesntExist
    }.should raise_error(NameError) {|e| e.receiver.should equal(Object) }
  end

  it "returns a class when an undefined constant is called" do
    -> {
      NameErrorSpecs::ReceiverClass::DoesntExist
    }.should raise_error(NameError) {|e| e.receiver.should equal(NameErrorSpecs::ReceiverClass) }
  end

  it "returns the Object class when an undefined class variable is called" do
    -> {
      eval("class singleton_class::A; @@doesnt_exist end", binding, __FILE__, __LINE__)
    }.should raise_error(NameError) {|e| e.receiver.should equal(singleton_class::A) }
  end

  it "returns a class when an undefined class variable is called in a subclass' namespace" do
    -> {
      NameErrorSpecs::ReceiverClass.new.call_undefined_class_variable
    }.should raise_error(NameError) {|e| e.receiver.should equal(NameErrorSpecs::ReceiverClass) }
  end

  it "returns the receiver when raised from #instance_variable_get" do
    receiver = Object.new

    -> {
      receiver.instance_variable_get("invalid_ivar_name")
    }.should raise_error(NameError) {|e| e.receiver.should equal(receiver) }
  end

  it "returns the receiver when raised from #class_variable_get" do
    -> {
      Object.class_variable_get("invalid_cvar_name")
    }.should raise_error(NameError) {|e| e.receiver.should equal(Object) }
  end

  it "raises an ArgumentError when the receiver is none" do
    -> { NameError.new.receiver }.should raise_error(ArgumentError)
  end
end
