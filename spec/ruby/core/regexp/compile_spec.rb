require_relative '../../spec_helper'
require_relative 'shared/new'

describe "Regexp.compile" do
  it_behaves_like :regexp_new, :compile
end

describe "Regexp.compile given a String" do
  it_behaves_like :regexp_new_string, :compile
  it_behaves_like :regexp_new_string_binary, :compile
end

describe "Regexp.compile given a Regexp" do
  it_behaves_like :regexp_new_regexp, :compile
end

describe "Regexp.new given a non-String/Regexp" do
  it_behaves_like :regexp_new_non_string_or_regexp, :compile
end
