require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/include', __FILE__)
require 'set'

describe "Set#include?" do
  it_behaves_like :set_include, :include?
end
