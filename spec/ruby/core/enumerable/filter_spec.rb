require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/find_all', __FILE__)

ruby_version_is "2.6" do
  describe "Enumerable#filter" do
    it_behaves_like(:enumerable_find_all , :filter)
  end
end
