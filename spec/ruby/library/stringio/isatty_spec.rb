require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/isatty'

describe "StringIO#isatty" do
  it_behaves_like :stringio_isatty, :isatty
end
