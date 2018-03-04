require_relative '../../spec_helper'
require_relative '../../shared/basicobject/send'

describe "BasicObject#__send__" do
  it "is a public instance method" do
    BasicObject.should have_public_instance_method(:__send__)
  end

  it_behaves_like :basicobject_send, :__send__
end
