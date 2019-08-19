require_relative '../../spec_helper'
require_relative 'shared/arg'

describe "Complex#angle" do
  it_behaves_like :complex_arg, :angle
end
