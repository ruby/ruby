require_relative "../../spec_helper"
require_relative 'shared/chars'
require_relative 'shared/each_char_without_block'

describe "String#each_char" do
  it_behaves_like :string_chars, :each_char
  it_behaves_like :string_each_char_without_block, :each_char
end
