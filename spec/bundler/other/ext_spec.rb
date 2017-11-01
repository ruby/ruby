# frozen_string_literal: true

RSpec.describe "Gem::Specification#match_platform" do
  it "does not match platforms other than the gem platform" do
    darwin = gem "lol", "1.0", "platform_specific-1.0-x86-darwin-10"
    expect(darwin.match_platform(pl("java"))).to eq(false)
  end

  context "when platform is a string" do
    it "matches when platform is a string" do
      lazy_spec = Bundler::LazySpecification.new("lol", "1.0", "universal-mingw32")
      expect(lazy_spec.match_platform(pl("x86-mingw32"))).to eq(true)
      expect(lazy_spec.match_platform(pl("x64-mingw32"))).to eq(true)
    end
  end
end

RSpec.describe "Bundler::GemHelpers#generic" do
  include Bundler::GemHelpers

  it "converts non-windows platforms into ruby" do
    expect(generic(pl("x86-darwin-10"))).to eq(pl("ruby"))
    expect(generic(pl("ruby"))).to eq(pl("ruby"))
  end

  it "converts java platform variants into java" do
    expect(generic(pl("universal-java-17"))).to eq(pl("java"))
    expect(generic(pl("java"))).to eq(pl("java"))
  end

  it "converts mswin platform variants into x86-mswin32" do
    expect(generic(pl("mswin32"))).to eq(pl("x86-mswin32"))
    expect(generic(pl("i386-mswin32"))).to eq(pl("x86-mswin32"))
    expect(generic(pl("x86-mswin32"))).to eq(pl("x86-mswin32"))
  end

  it "converts 32-bit mingw platform variants into x86-mingw32" do
    expect(generic(pl("mingw32"))).to eq(pl("x86-mingw32"))
    expect(generic(pl("i386-mingw32"))).to eq(pl("x86-mingw32"))
    expect(generic(pl("x86-mingw32"))).to eq(pl("x86-mingw32"))
  end

  it "converts 64-bit mingw platform variants into x64-mingw32" do
    expect(generic(pl("x64-mingw32"))).to eq(pl("x64-mingw32"))
    expect(generic(pl("x86_64-mingw32"))).to eq(pl("x64-mingw32"))
  end
end

RSpec.describe "Gem::SourceIndex#refresh!" do
  before do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  it "does not explode when called", :rubygems => "1.7" do
    run "Gem.source_index.refresh!"
    run "Gem::SourceIndex.new([]).refresh!"
  end

  it "does not explode when called", :rubygems => "< 1.7" do
    run "Gem.source_index.refresh!"
    run "Gem::SourceIndex.from_gems_in([]).refresh!"
  end
end
