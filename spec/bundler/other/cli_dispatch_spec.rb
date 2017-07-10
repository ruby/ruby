# frozen_string_literal: true
require "spec_helper"

describe "bundle command names" do
  it "work when given fully" do
    bundle "install"
    expect(err).to lack_errors
    expect(out).not_to match(/Ambiguous command/)
  end

  it "work when not ambiguous" do
    bundle "ins"
    expect(err).to lack_errors
    expect(out).not_to match(/Ambiguous command/)
  end

  it "print a friendly error when ambiguous" do
    bundle "in"
    expect(err).to lack_errors
    expect(out).to match(/Ambiguous command/)
  end
end
