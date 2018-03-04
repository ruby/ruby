# -*- encoding: ascii-8bit -*-
require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/cover'

describe "Range#cover?" do
  it_behaves_like :range_cover_and_include, :cover?
  it_behaves_like :range_cover, :cover?
end
