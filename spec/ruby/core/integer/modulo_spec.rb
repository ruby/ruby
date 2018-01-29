require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/modulo', __FILE__)

describe "Integer#%" do
  it_behaves_like :integer_modulo, :%
end

describe "Integer#modulo" do
  it_behaves_like :integer_modulo, :modulo
end
