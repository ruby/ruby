require_relative '../../spec_helper'
require_relative 'shared/new'

# NOTE: should be syncronized with library/stringio/initialize_spec.rb

describe "IO.new" do
  it_behaves_like :io_new, :new
end

describe "IO.new" do
  it_behaves_like :io_new_errors, :new
end
