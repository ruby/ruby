require_relative '../../spec_helper'
require_relative 'shared/tty'

describe "IO#isatty" do
  it_behaves_like :io_tty, :isatty
end
