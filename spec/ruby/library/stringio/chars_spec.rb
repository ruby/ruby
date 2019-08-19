require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/each_char'

describe "StringIO#chars" do
  it_behaves_like :stringio_each_char, :chars
end

describe "StringIO#chars when self is not readable" do
  it_behaves_like :stringio_each_char_not_readable, :chars
end
