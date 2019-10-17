require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/pos'

describe "IO#pos" do
  it_behaves_like :io_pos, :pos
end

describe "IO#pos=" do
  it_behaves_like :io_set_pos, :pos=
end
