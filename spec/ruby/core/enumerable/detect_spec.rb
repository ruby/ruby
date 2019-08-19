require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/find'

describe "Enumerable#detect" do
  it_behaves_like :enumerable_find , :detect
end
