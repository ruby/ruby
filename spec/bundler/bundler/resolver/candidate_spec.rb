# frozen_string_literal: true

RSpec.describe Bundler::Resolver::Candidate do
  it "compares fine" do
    version1 = described_class.new("1.12.5", :specs => [Gem::Specification.new("foo", "1.12.5") {|s| s.platform = Gem::Platform::RUBY }])
    version2 = described_class.new("1.12.5")

    expect(version1 >= version2).to be true
  end
end
