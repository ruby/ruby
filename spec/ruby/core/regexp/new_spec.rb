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
  it_behaves_like :regexp_new_string_binary, :compile
end

describe "Regexp.new given a Fixnum" do
  it "raises a TypeError" do
    -> { Regexp.new(1) }.should raise_error(TypeError)
  end
end

describe "Regexp.new given a Float" do
  it "raises a TypeError" do
    -> { Regexp.new(1.0) }.should raise_error(TypeError)
  end
end
