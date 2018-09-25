require_relative '../../spec_helper'
require_relative 'shared/conj'

describe "Numeric#conj" do
  it_behaves_like :numeric_conj, :conj
end
