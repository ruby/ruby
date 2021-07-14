require_relative '../../spec_helper'
require_relative 'shared/load'

guard -> { Psych::VERSION >= "4.0.0" } do
  describe "YAML.unsafe_load" do
    it_behaves_like :yaml_load_safe, :unsafe_load
    it_behaves_like :yaml_load_unsafe, :unsafe_load
  end
end
