# frozen_string_literal: true

RSpec.describe Bundler::Resolver::Candidate do
  it "compares fine" do
    version1 = described_class.new("1.12.5", specs: [Gem::Specification.new("foo", "1.12.5") {|s| s.platform = Gem::Platform::RUBY }])
    version2 = described_class.new("1.12.5") # passing no specs creates a platform specific candidate, so sorts higher

    expect(version2 >= version1).to be true

    expect(version1.generic! == version2.generic!).to be true
    expect(version1.platform_specific! == version2.platform_specific!).to be true

    expect(version1.platform_specific! >= version2.generic!).to be true
    expect(version2.platform_specific! >= version1.generic!).to be true

    version1 = described_class.new("1.12.5", specs: [Gem::Specification.new("foo", "1.12.5") {|s| s.platform = Gem::Platform::RUBY }])
    version2 = described_class.new("1.12.5", specs: [Gem::Specification.new("foo", "1.12.5") {|s| s.platform = Gem::Platform::X64_LINUX }])

    expect(version2 >= version1).to be true
  end
end
