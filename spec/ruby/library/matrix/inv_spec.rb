require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'shared/inverse'

describe "Matrix#inv" do
  it_behaves_like :inverse, :inv
end
