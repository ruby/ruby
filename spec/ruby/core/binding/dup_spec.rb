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
end
