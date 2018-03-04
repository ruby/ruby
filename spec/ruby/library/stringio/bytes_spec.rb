require_relative '../../spec_helper'
require 'stringio'
require_relative 'shared/each_byte'

describe "StringIO#bytes" do
  it_behaves_like :stringio_each_byte, :bytes
end

describe "StringIO#bytes when self is not readable" do
  it_behaves_like :stringio_each_byte_not_readable, :bytes
end
