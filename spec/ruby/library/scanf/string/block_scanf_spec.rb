require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../shared/block_scanf.rb', __FILE__)
require 'scanf'

describe "String#block_scanf" do
  it_behaves_like :scanf_string_block_scanf, :block_scanf
end
