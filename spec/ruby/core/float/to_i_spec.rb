require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/to_i', __FILE__)

describe "Float#to_i" do
  it_behaves_like(:float_to_i, :to_i)
end
