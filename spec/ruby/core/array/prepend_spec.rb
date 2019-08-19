require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/unshift'

ruby_version_is "2.5" do
  describe "Array#prepend" do
    it_behaves_like :array_unshift, :prepend
  end
end
