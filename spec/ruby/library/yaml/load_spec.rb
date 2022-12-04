require_relative '../../spec_helper'
require_relative 'shared/load'

describe "YAML.load" do
  it_behaves_like :yaml_load_safe, :load

  guard -> { Psych::VERSION < "4.0.0" } do
    it_behaves_like :yaml_load_unsafe, :load
  end
end
