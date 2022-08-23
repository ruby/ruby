# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/slice'

describe "String#slice" do
  it_behaves_like :string_slice, :slice
end

describe "String#slice with index, length" do
  it_behaves_like :string_slice_index_length, :slice
end

describe "String#slice with Range" do
  it_behaves_like :string_slice_range, :slice
end

describe "String#slice with Regexp" do
  it_behaves_like :string_slice_regexp, :slice
end

describe "String#slice with Regexp, index" do
  it_behaves_like :string_slice_regexp_index, :slice
end

describe "String#slice with Regexp, group" do
  it_behaves_like :string_slice_regexp_group, :slice
end

describe "String#slice with String" do
  it_behaves_like :string_slice_string, :slice
end

describe "String#slice with Symbol" do
  it_behaves_like :string_slice_symbol, :slice
end

describe "String#slice! with index" do
  it_behaves_like :string_slice_bang, :slice!
end

describe "String#slice! with index, length" do
  it_behaves_like :string_slice_bang_index_length, :slice!
end

describe "String#slice! Range" do
  it_behaves_like :string_slice_bang_range, :slice!
end

describe "String#slice! with Regexp" do
  it_behaves_like :string_slice_bang_regexp, :slice!
end

describe "String#slice! with Regexp, index" do
  it_behaves_like :string_slice_bang_regexp_index, :slice!
end

describe "String#slice! with String" do
  it_behaves_like :string_slice_bang_string, :slice!
end
