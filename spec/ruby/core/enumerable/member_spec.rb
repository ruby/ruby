require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/include'

describe "Enumerable#member?" do
  it_behaves_like :enumerable_include, :member?
end
