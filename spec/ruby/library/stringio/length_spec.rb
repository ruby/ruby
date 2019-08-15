require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "StringIO#length" do
  it_behaves_like :stringio_length, :length
end
