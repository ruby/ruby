require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/find_all'

ruby_version_is "2.6" do
  describe "Enumerable#filter" do
    it_behaves_like(:enumerable_find_all , :filter)
  end
end
