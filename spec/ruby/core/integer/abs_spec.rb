require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/abs', __FILE__)

describe "Integer#abs" do
  it_behaves_like :integer_abs, :abs
end

