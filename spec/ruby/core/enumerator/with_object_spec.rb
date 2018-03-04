require_relative '../../spec_helper'
require_relative '../../shared/enumerator/with_object'

describe "Enumerator#with_object" do
  it_behaves_like :enum_with_object, :with_object
end
