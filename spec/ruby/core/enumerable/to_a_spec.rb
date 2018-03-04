require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/entries'

describe "Enumerable#to_a" do
  it_behaves_like :enumerable_entries , :to_a
end
