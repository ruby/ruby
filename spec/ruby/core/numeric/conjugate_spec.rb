require_relative '../../spec_helper'
require_relative 'shared/conj'

describe "Numeric#conjugate" do
  it_behaves_like :numeric_conj, :conjugate
end
