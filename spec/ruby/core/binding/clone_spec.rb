require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/clone'

describe "Binding#clone" do
  it_behaves_like :binding_clone, :clone

  it "preserves frozen status" do
    bind = binding.freeze
    bind.frozen?.should == true
    bind.clone.frozen?.should == true
  end
end
