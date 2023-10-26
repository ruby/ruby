# frozen_string_literal: true

RSpec.describe "bundle install with install_if conditionals" do
  it "follows the install_if DSL" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      install_if(lambda { true }) do
        gem "activesupport", "2.3.5"
      end
      gem "thin", :install_if => false
      install_if(lambda { false }) do
        gem "foo"
      end
      gem "rack"
    G

    expect(the_bundle).to include_gems("rack 1.0", "activesupport 2.3.5")
    expect(the_bundle).not_to include_gems("thin")
    expect(the_bundle).not_to include_gems("foo")

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          activesupport (2.3.5)
          foo (1.0)
          rack (1.0.0)
          thin (1.0)
            rack

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        activesupport (= 2.3.5)
        foo
        rack
        thin

      CHECKSUMS
        #{checksum_for_repo_gem gem_repo1, "activesupport", "2.3.5"}
        #{gem_no_checksum "foo", "1.0"}
        #{checksum_for_repo_gem gem_repo1, "rack", "1.0.0"}
        #{gem_no_checksum "thin", "1.0"}

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end
