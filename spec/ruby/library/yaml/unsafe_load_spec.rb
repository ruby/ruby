require_relative '../../spec_helper'
require_relative 'shared/load'

ruby_version_is "3.1" do
  describe "YAML.unsafe_load" do
    it_behaves_like :yaml_load, :unsafe_load
  end
end
