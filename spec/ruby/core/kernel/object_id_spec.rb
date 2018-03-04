require_relative '../../spec_helper'
require_relative '../../shared/kernel/object_id'

describe "Kernel#object_id" do
  it_behaves_like :object_id, :object_id, Object
end
