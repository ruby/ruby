require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'shared/inverse'

describe "Matrix#inverse" do
  it_behaves_like :inverse, :inverse
end
