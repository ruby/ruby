require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/each_char'

describe "StringIO#each_char" do
  it_behaves_like :stringio_each_char, :each_char
end

describe "StringIO#each_char when self is not readable" do
  it_behaves_like :stringio_each_char_not_readable, :chars
end
