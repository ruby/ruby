require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/push'

describe "Array#push" do
  it_behaves_like :array_push, :push
end
