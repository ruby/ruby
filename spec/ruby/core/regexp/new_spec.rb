require_relative '../../spec_helper'
require_relative 'shared/new'

describe "Regexp.new" do
  it_behaves_like :regexp_new, :new
end

describe "Regexp.new given a String" do
  it_behaves_like :regexp_new_string, :new
end

describe "Regexp.new given a Regexp" do
  it_behaves_like :regexp_new_regexp, :new
  it_behaves_like :regexp_new_string_binary, :new
end

describe "Regexp.new given a non-String/Regexp" do
  it_behaves_like :regexp_new_non_string_or_regexp, :new
end
