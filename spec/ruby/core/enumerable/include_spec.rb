require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/include', __FILE__)

describe "Enumerable#include?" do
  it_behaves_like :enumerable_include, :include?
end
