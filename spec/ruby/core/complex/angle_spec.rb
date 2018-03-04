require_relative '../../spec_helper'

require_relative '../../shared/complex/arg'

describe "Complex#angle" do
  it_behaves_like :complex_arg, :angle
end
