require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#global_variables" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:global_variables)
  end

  before :all do
    @i = 0
  end

  it "finds subset starting with std" do
    global_variables.grep(/std/).to_set.should >= Set[:$stderr, :$stdin, :$stdout]
    a = global_variables.size
    gvar_name = "$foolish_global_var#{@i += 1}"
    global_variables.include?(gvar_name.to_sym).should == false
    eval("#{gvar_name} = 1")
    global_variables.size.should == a+1
    global_variables.should.include?(gvar_name.to_sym)
  end
end

describe "Kernel.global_variables" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:global_variables)
  end
end
