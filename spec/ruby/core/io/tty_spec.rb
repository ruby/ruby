require_relative '../../spec_helper'
require_relative 'shared/tty'

describe "IO#tty?" do
  it_behaves_like :io_tty, :tty?
end
