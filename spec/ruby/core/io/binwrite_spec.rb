require_relative '../../spec_helper'
require_relative 'shared/binwrite'

describe "IO.binwrite" do
  it_behaves_like :io_binwrite, :binwrite
end
