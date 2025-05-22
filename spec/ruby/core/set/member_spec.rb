require_relative '../../spec_helper'
require_relative 'shared/include'

describe "Set#member?" do
  it_behaves_like :set_include, :member?
end
