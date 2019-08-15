require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each_line'
require_relative 'shared/each_line_without_block'

describe "String#each_line" do
  it_behaves_like :string_each_line, :each_line
  it_behaves_like :string_each_line_without_block, :each_line
end
