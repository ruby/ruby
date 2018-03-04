require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/succ'

describe "String#succ" do
  it_behaves_like :string_succ, :succ
end

describe "String#succ!" do
  it_behaves_like :string_succ_bang, :"succ!"
end
