require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/inject'

describe "Enumerable#reduce" do
  it_behaves_like :enumerable_inject, :reduce
end
