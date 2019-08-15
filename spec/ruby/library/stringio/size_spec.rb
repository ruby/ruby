require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "StringIO#size" do
  it_behaves_like :stringio_length, :size
end
