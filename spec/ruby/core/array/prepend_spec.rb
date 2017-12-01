require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/unshift', __FILE__)

ruby_version_is "2.5" do
  describe "Array#prepend" do
    it_behaves_like(:array_unshift, :prepend)
  end
end
