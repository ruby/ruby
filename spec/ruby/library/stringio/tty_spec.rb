require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/isatty'

describe "StringIO#tty?" do
  it_behaves_like :stringio_isatty, :tty?
end
