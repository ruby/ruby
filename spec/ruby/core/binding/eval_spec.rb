require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Binding#eval" do
  it "behaves like Kernel.eval(..., self)" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_binding

    bind.eval("@secret += square(3)").should == 10
    bind.eval("a").should be_true

    bind.eval("class Inside; end")
    bind.eval("Inside.name").should == "BindingSpecs::Demo::Inside"
  end

  it "does not leak variables to cloned bindings" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_empty_binding
    bind2 = bind.dup

    bind.eval("x = 72")
    bind.local_variables.should == [:x]
    bind2.local_variables.should == []
  end

  it "inherits __LINE__ from the enclosing scope" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_binding
    bind.eval("__LINE__").should == obj.get_line_of_binding
  end

  it "preserves __LINE__ across multiple calls to eval" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_binding
    bind.eval("__LINE__").should == obj.get_line_of_binding
    bind.eval("__LINE__").should == obj.get_line_of_binding
  end

  it "increments __LINE__ on each line of a multiline eval" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_binding
    bind.eval("#foo\n__LINE__").should == obj.get_line_of_binding + 1
  end

  it "inherits __LINE__ from the enclosing scope even if the Binding is created with #send" do
    obj = BindingSpecs::Demo.new(1)
    bind, line = obj.get_binding_with_send_and_line
    bind.eval("__LINE__").should == line
  end

  it "starts with a __LINE__ of 1 if a filename is passed" do
    bind = BindingSpecs::Demo.new(1).get_binding
    bind.eval("__LINE__", "(test)").should == 1
    bind.eval("#foo\n__LINE__", "(test)").should == 2
  end

  it "starts with a __LINE__ from the third argument if passed" do
    bind = BindingSpecs::Demo.new(1).get_binding
    bind.eval("__LINE__", "(test)", 88).should == 88
    bind.eval("#foo\n__LINE__", "(test)", 88).should == 89
  end

  it "inherits __FILE__ from the enclosing scope" do
    obj = BindingSpecs::Demo.new(1)
    bind = obj.get_binding
    bind.eval("__FILE__").should == obj.get_file_of_binding
  end

  it "uses the __FILE__ that is passed in" do
    bind = BindingSpecs::Demo.new(1).get_binding
    bind.eval("__FILE__", "(test)").should == "(test)"
  end

  describe "with a file given" do
    it "does not store the filename permanently" do
      obj = BindingSpecs::Demo.new(1)
      bind = obj.get_binding

      bind.eval("__FILE__", "test.rb").should == "test.rb"
      bind.eval("__FILE__").should_not == "test.rb"
    end
  end

  it "with __method__ returns the method where the Binding was created" do
    obj = BindingSpecs::Demo.new(1)
    bind, meth = obj.get_binding_and_method
    bind.eval("__method__").should == meth
  end

  it "with __method__ returns the method where the Binding was created, ignoring #send" do
    obj = BindingSpecs::Demo.new(1)
    bind, meth = obj.get_binding_with_send_and_method
    bind.eval("__method__").should == meth
  end
end
