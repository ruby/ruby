require_relative '../../spec_helper'
require_relative 'shared/include'
require 'set'

ruby_version_is "2.5" do
  describe "Set#===" do
    it_behaves_like :set_include, :===
  end
end
