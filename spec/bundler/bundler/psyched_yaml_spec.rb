# frozen_string_literal: true
require "spec_helper"
require "bundler/psyched_yaml"

RSpec.describe "Bundler::YamlLibrarySyntaxError" do
  it "is raised on YAML parse errors" do
    expect { YAML.parse "{foo" }.to raise_error(Bundler::YamlLibrarySyntaxError)
  end
end
