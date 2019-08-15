require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each'

describe "IO#each" do
  it_behaves_like :io_each, :each
end

describe "IO#each" do
  it_behaves_like :io_each_default_separator, :each
end
