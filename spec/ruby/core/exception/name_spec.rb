require_relative '../../spec_helper'

describe "NameError#name" do
  it "returns a method name as a symbol" do
    -> {
      doesnt_exist
    }.should raise_error(NameError) {|e| e.name.should == :doesnt_exist }
  end

  it "returns a constant name as a symbol" do
    -> {
      DoesntExist
    }.should raise_error(NameError) {|e| e.name.should == :DoesntExist }
  end

  it "returns a constant name without namespace as a symbol" do
    -> {
      Object::DoesntExist
    }.should raise_error(NameError) {|e| e.name.should == :DoesntExist }
  end

  it "returns a class variable name as a symbol" do
    -> {
      eval("class singleton_class::A; @@doesnt_exist end", binding, __FILE__, __LINE__)
    }.should raise_error(NameError) { |e| e.name.should == :@@doesnt_exist }
  end

  it "returns the first argument passed to the method when a NameError is raised from #instance_variable_get" do
    invalid_ivar_name = "invalid_ivar_name"

    -> {
      Object.new.instance_variable_get(invalid_ivar_name)
    }.should raise_error(NameError) {|e| e.name.should equal(invalid_ivar_name) }
  end

  it "returns the first argument passed to the method when a NameError is raised from #class_variable_get" do
    invalid_cvar_name = "invalid_cvar_name"

    -> {
      Object.class_variable_get(invalid_cvar_name)
    }.should raise_error(NameError) {|e| e.name.should equal(invalid_cvar_name) }
  end
end
