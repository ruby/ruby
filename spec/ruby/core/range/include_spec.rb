# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/include'
require_relative 'shared/cover'

describe "Range#include?" do
  it_behaves_like :range_cover_and_include, :include?
  it_behaves_like :range_include, :include?

  it "does not include U+9995 in the range U+0999..U+9999" do
    ("\u{999}".."\u{9999}").include?("\u{9995}").should be_false
  end
end
