require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/clone'

describe "Binding#dup" do
  it_behaves_like :binding_clone, :dup

  it "resets frozen status" do
    bind = binding.freeze
    bind.frozen?.should == true
    bind.dup.frozen?.should == false
  end

  it "retains original binding variables but the list is distinct" do
    bind1 = binding
    eval "a = 1", bind1

    bind2 = bind1.dup
    eval("a = 2", bind2)
    eval("a", bind1).should == 2
    eval("a", bind2).should == 2

    eval("b = 2", bind2)
    -> { eval("b", bind1) }.should raise_error(NameError)
    eval("b", bind2).should == 2

    bind1.local_variables.sort.should == [:a, :bind1, :bind2]
    bind2.local_variables.sort.should == [:a, :b, :bind1, :bind2]
  end
end
