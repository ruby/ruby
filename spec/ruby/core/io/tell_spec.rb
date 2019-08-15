require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/pos'

describe "IO#tell" do
  it_behaves_like :io_pos, :tell
end
