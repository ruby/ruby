require_relative '../../../spec_helper'
require_relative 'shared/block_scanf'
require 'scanf'

describe "IO#block_scanf" do
  it_behaves_like :scanf_io_block_scanf, :block_scanf
end
