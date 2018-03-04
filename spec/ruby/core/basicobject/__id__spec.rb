require_relative '../../spec_helper'
require_relative '../../shared/kernel/object_id'

describe "BasicObject#__id__" do
  it_behaves_like :object_id, :__id__, BasicObject
end
