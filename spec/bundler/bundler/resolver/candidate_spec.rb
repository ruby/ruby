# frozen_string_literal: true

RSpec.describe Bundler::Resolver::Candidate do
  it "compares fine" do
    version1 = described_class.new("1.12.5", priority: -1)
    version2 = described_class.new("1.12.5", priority: 1)

    expect(version2 > version1).to be true

    version1 = described_class.new("1.12.5")
    version2 = described_class.new("1.12.5")

    expect(version2 == version1).to be true

    version1 = described_class.new("1.12.5", priority: 1)
    version2 = described_class.new("1.12.5", priority: -1)

    expect(version2 < version1).to be true
  end
end
