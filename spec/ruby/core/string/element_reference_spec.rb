require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/slice'

describe "String#[]" do
  it_behaves_like :string_slice, :[]
end

describe "String#[] with index, length" do
  it_behaves_like :string_slice_index_length, :[]
end

describe "String#[] with Range" do
  it_behaves_like :string_slice_range, :[]
end

describe "String#[] with Regexp" do
  it_behaves_like :string_slice_regexp, :[]
end

describe "String#[] with Regexp, index" do
  it_behaves_like :string_slice_regexp_index, :[]
end

describe "String#[] with Regexp, group" do
  it_behaves_like :string_slice_regexp_group, :[]
end

describe "String#[] with String" do
  it_behaves_like :string_slice_string, :[]
end

describe "String#[] with Symbol" do
  it_behaves_like :string_slice_symbol, :[]
end
