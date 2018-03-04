require_relative '../../spec_helper'
require_relative 'shared/include'
require 'set'

describe "Set#include?" do
  it_behaves_like :set_include, :include?
end
