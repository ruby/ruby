require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/include'

describe "Enumerable#include?" do
  it_behaves_like :enumerable_include, :include?
end
