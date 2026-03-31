# frozen_string_literal: true

RSpec.describe "Gem::Specification#installable_on_platform?" do
  it "does not match platforms other than the gem platform" do
    darwin = gem "lol", "1.0", "platform_specific-1.0-x86-darwin-10"
    expect(darwin.installable_on_platform?(pl("java"))).to eq(false)
  end

  context "when platform is a string" do
    it "matches when platform is a string" do
      lazy_spec = Bundler::LazySpecification.new("lol", "1.0", "universal-mingw32")
      expect(lazy_spec.installable_on_platform?(pl("x86-mingw32"))).to eq(true)
      expect(lazy_spec.installable_on_platform?(pl("x64-mingw32"))).to eq(true)
    end
  end
end

RSpec.describe "Gem::SourceIndex#refresh!" do
  before do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  it "does not explode when called" do
    run "Gem.source_index.refresh!", raise_on_error: false
    run "Gem::SourceIndex.new([]).refresh!", raise_on_error: false
  end
end

RSpec.describe "Gem::NameTuple" do
  describe "#initialize" do
    it "creates a Gem::NameTuple with equality regardless of platform type" do
      gem_platform = Gem::NameTuple.new "a", v("1"), pl("x86_64-linux")
      str_platform = Gem::NameTuple.new "a", v("1"), "x86_64-linux"
      expect(gem_platform).to eq(str_platform)
      expect(gem_platform.hash).to eq(str_platform.hash)
      expect(gem_platform.to_a).to eq(str_platform.to_a)
    end
  end

  describe "#lock_name" do
    it "returns the lock name" do
      expect(Gem::NameTuple.new("a", v("1.0.0"), pl("x86_64-linux")).lock_name).to eq("a (1.0.0-x86_64-linux)")
      expect(Gem::NameTuple.new("a", v("1.0.0"), "ruby").lock_name).to eq("a (1.0.0)")
      expect(Gem::NameTuple.new("a", v("1.0.0")).lock_name).to eq("a (1.0.0)")
    end
  end
end
