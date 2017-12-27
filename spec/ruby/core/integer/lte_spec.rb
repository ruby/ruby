require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/comparison_exception_in_coerce', __FILE__)

describe "Integer#<=" do
  it_behaves_like :integer_comparison_exception_in_coerce, :<=
end
