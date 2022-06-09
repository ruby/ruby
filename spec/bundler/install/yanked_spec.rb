# frozen_string_literal: true

RSpec.context "when installing a bundle that includes yanked gems" do
  before(:each) do
    build_repo4 do
      build_gem "foo", "9.0.0"
    end
  end

  it "throws an error when the original gem version is yanked" do
    lockfile <<-L
       GEM
         remote: #{file_uri_for(gem_repo4)}
         specs:
           foo (10.0.0)

       PLATFORMS
         ruby

       DEPENDENCIES
         foo (= 10.0.0)

    L

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo4)}"
      gem "foo", "10.0.0"
    G

    expect(err).to include("Your bundle is locked to foo (10.0.0)")
  end

  it "throws the original error when only the Gemfile specifies a gem version that doesn't exist" do
    bundle "config set force_ruby_platform true"

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo4)}"
      gem "foo", "10.0.0"
    G

    expect(err).not_to include("Your bundle is locked to foo (10.0.0)")
    expect(err).to include("Could not find gem 'foo (= 10.0.0)' in")
  end
end

RSpec.context "when using gem before installing" do
  it "does not suggest the author has yanked the gem" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
    G

    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo1)}
        specs:
          rack (0.9.1)

      PLATFORMS
        ruby

      DEPENDENCIES
        rack (= 0.9.1)
    L

    bundle :list, :raise_on_error => false

    expect(err).to include("Could not find rack-0.9.1 in any of the sources")
    expect(err).to_not include("Your bundle is locked to rack (0.9.1) from")
    expect(err).to_not include("If you haven't changed sources, that means the author of rack (0.9.1) has removed it.")
    expect(err).to_not include("You'll need to update your bundle to a different version of rack (0.9.1) that hasn't been removed in order to install.")
  end

  it "does not suggest the author has yanked the gem when using more than one gem, but shows all gems that couldn't be found in the source" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
      gem "rack_middleware", "1.0"
    G

    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo1)}
        specs:
          rack (0.9.1)
          rack_middleware (1.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rack (= 0.9.1)
        rack_middleware (1.0)
    L

    bundle :list, :raise_on_error => false

    expect(err).to include("Could not find rack-0.9.1, rack_middleware-1.0 in any of the sources")
    expect(err).to include("Install missing gems with `bundle install`.")
    expect(err).to_not include("Your bundle is locked to rack (0.9.1) from")
    expect(err).to_not include("If you haven't changed sources, that means the author of rack (0.9.1) has removed it.")
    expect(err).to_not include("You'll need to update your bundle to a different version of rack (0.9.1) that hasn't been removed in order to install.")
  end
end
