require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each'

describe "IO#each_line" do
  it_behaves_like :io_each, :each_line
end

describe "IO#each_line" do
  it_behaves_like :io_each_default_separator, :each_line
end
