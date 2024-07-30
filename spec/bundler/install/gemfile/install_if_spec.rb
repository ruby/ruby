# frozen_string_literal: true

RSpec.describe "bundle install with install_if conditionals" do
  it "follows the install_if DSL" do
    install_gemfile <<-G
      source "https://gem.repo1"
      install_if(lambda { true }) do
        gem "activesupport", "2.3.5"
      end
      gem "thin", :install_if => false
      install_if(lambda { false }) do
        gem "foo"
      end
      gem "myrack"
    G

    expect(the_bundle).to include_gems("myrack 1.0", "activesupport 2.3.5")
    expect(the_bundle).not_to include_gems("thin")
    expect(the_bundle).not_to include_gems("foo")

    checksums = checksums_section_when_enabled do |c|
      c.checksum gem_repo1, "activesupport", "2.3.5"
      c.checksum gem_repo1, "foo", "1.0"
      c.checksum gem_repo1, "myrack", "1.0.0"
      c.checksum gem_repo1, "thin", "1.0"
    end

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo1/
        specs:
          activesupport (2.3.5)
          foo (1.0)
          myrack (1.0.0)
          thin (1.0)
            myrack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport (= 2.3.5)
        foo
        myrack
        thin
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end
