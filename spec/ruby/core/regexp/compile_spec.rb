require_relative '../../spec_helper'
require_relative 'shared/new_ascii'
require_relative 'shared/new_ascii_8bit'

describe "Regexp.compile" do
  it_behaves_like :regexp_new_ascii, :compile
  it_behaves_like :regexp_new_ascii_8bit, :compile
end

describe "Regexp.compile given a String" do
  it_behaves_like :regexp_new_string_ascii, :compile
  it_behaves_like :regexp_new_string_ascii_8bit, :compile
end

describe "Regexp.compile given a Regexp" do
  it_behaves_like :regexp_new_regexp_ascii, :compile
  it_behaves_like :regexp_new_regexp_ascii_8bit, :compile
end
