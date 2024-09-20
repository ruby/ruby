# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/cover'

describe "Range#cover?" do
  it_behaves_like :range_cover_and_include, :cover?
  it_behaves_like :range_cover, :cover?
  it_behaves_like :range_cover_subrange, :cover?

  it "covers U+9995 in the range U+0999..U+9999" do
    ("\u{999}".."\u{9999}").cover?("\u{9995}").should be_true
  end
end
