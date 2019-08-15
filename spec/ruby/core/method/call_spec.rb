require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/call'

describe "Method#call" do
  it_behaves_like :method_call, :call
end
