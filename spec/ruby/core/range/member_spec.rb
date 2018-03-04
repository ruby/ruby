# -*- encoding: ascii-8bit -*-
require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/include'
require_relative 'shared/cover'

describe "Range#member?" do
  it_behaves_like :range_cover_and_include, :member?
  it_behaves_like :range_include, :member?
end
