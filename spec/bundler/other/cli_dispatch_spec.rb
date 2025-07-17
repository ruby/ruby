# frozen_string_literal: true

RSpec.describe "bundle command names" do
  it "work when given fully" do
    bundle "install", raise_on_error: false
    expect(err).to eq("Could not locate Gemfile")
    expect(stdboth).not_to include("Ambiguous command")
  end

  it "work when not ambiguous" do
    bundle "ins", raise_on_error: false
    expect(err).to eq("Could not locate Gemfile")
    expect(stdboth).not_to include("Ambiguous command")
  end

  it "print a friendly error when ambiguous" do
    bundle "in", raise_on_error: false
    expect(err).to eq("Ambiguous command in matches [info, init, inject, install]")
  end
end
