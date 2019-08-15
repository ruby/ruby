require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/succ'

describe "String#next" do
  it_behaves_like :string_succ, :next
end

describe "String#next!" do
  it_behaves_like :string_succ_bang, :"next!"
end
