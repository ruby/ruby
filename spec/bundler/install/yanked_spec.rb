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
         remote: https://gem.repo4
         specs:
           foo (10.0.0)

       PLATFORMS
         #{lockfile_platforms}

       DEPENDENCIES
         foo (= 10.0.0)

    L

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo4"
      gem "foo", "10.0.0"
    G

    expect(err).to include("Your bundle is locked to foo (10.0.0)")
  end

  context "when a platform specific yanked version is included in the lockfile, and a generic variant is available remotely" do
    let(:original_lockfile) do
      <<~L
        GEM
          remote: https://gem.repo4/
          specs:
            actiontext (6.1.6)
              nokogiri (>= 1.8)
            foo (1.0.0)
            nokogiri (1.13.8-#{Bundler.local_platform})

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          actiontext (= 6.1.6)
          foo (= 1.0.0)

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    before do
      skip "Materialization on Windows is not yet strict, so the example does not detect the gem has been yanked" if Gem.win_platform?

      build_repo4 do
        build_gem "foo", "1.0.0"
        build_gem "foo", "1.0.1"
        build_gem "actiontext", "6.1.7" do |s|
          s.add_dependency "nokogiri", ">= 1.8"
        end
        build_gem "actiontext", "6.1.6" do |s|
          s.add_dependency "nokogiri", ">= 1.8"
        end
        build_gem "actiontext", "6.1.7" do |s|
          s.add_dependency "nokogiri", ">= 1.8"
        end
        build_gem "nokogiri", "1.13.8"
      end

      gemfile <<~G
        source "https://gem.repo4"
        gem "foo", "1.0.0"
        gem "actiontext", "6.1.6"
      G

      lockfile original_lockfile
    end

    context "and a re-resolve is necessary" do
      before do
        gemfile gemfile.sub('"foo", "1.0.0"', '"foo", "1.0.1"')
      end

      it "reresolves, and replaces the yanked gem with the generic version, printing a warning, when the old index is used" do
        bundle "install", artifice: "endpoint", verbose: true

        expect(out).to include("Installing nokogiri 1.13.8").and include("Installing foo 1.0.1")
        expect(lockfile).to eq(original_lockfile.sub("nokogiri (1.13.8-#{Bundler.local_platform})", "nokogiri (1.13.8)").gsub("1.0.0", "1.0.1"))
        expect(err).to include("Some locked specs have possibly been yanked (nokogiri-1.13.8-#{Bundler.local_platform}). Ignoring them...")
      end

      it "reresolves, and replaces the yanked gem with the generic version, printing a warning, when the compact index API is used" do
        bundle "install", artifice: "compact_index", verbose: true

        expect(out).to include("Installing nokogiri 1.13.8").and include("Installing foo 1.0.1")
        expect(lockfile).to eq(original_lockfile.sub("nokogiri (1.13.8-#{Bundler.local_platform})", "nokogiri (1.13.8)").gsub("1.0.0", "1.0.1"))
        expect(err).to include("Some locked specs have possibly been yanked (nokogiri-1.13.8-#{Bundler.local_platform}). Ignoring them...")
      end
    end

    it "reports the yanked gem properly when the old index is used" do
      bundle "install", artifice: "endpoint", raise_on_error: false

      expect(err).to include("Your bundle is locked to nokogiri (1.13.8-#{Bundler.local_platform})")
    end

    it "reports the yanked gem properly when the compact index API is used" do
      bundle "install", artifice: "compact_index", raise_on_error: false

      expect(err).to include("Your bundle is locked to nokogiri (1.13.8-#{Bundler.local_platform})")
    end
  end

  it "throws the original error when only the Gemfile specifies a gem version that doesn't exist" do
    bundle "config set force_ruby_platform true"

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo4"
      gem "foo", "10.0.0"
    G

    expect(err).not_to include("Your bundle is locked to foo (10.0.0)")
    expect(err).to include("Could not find gem 'foo (= 10.0.0)' in")
  end
end

RSpec.context "when resolving a bundle that includes yanked gems, but unlocking an unrelated gem" do
  before(:each) do
    build_repo4 do
      build_gem "foo", "10.0.0"

      build_gem "bar", "1.0.0"
      build_gem "bar", "2.0.0"
    end

    lockfile <<-L
      GEM
        remote: https://gem.repo4
        specs:
          foo (9.0.0)
          bar (1.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo
        bar

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    gemfile <<-G
      source "https://gem.repo4"
      gem "foo"
      gem "bar"
    G
  end

  it "does not update the yanked gem" do
    bundle "lock --update bar"

    expect(lockfile).to eq <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          bar (2.0.0)
          foo (9.0.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        bar
        foo

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end

RSpec.context "when using gem before installing" do
  it "does not suggest the author has yanked the gem" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", "0.9.1"
    G

    lockfile <<-L
      GEM
        remote: https://gem.repo1
        specs:
          myrack (0.9.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (= 0.9.1)
    L

    bundle :list, raise_on_error: false

    expect(err).to include("Could not find myrack-0.9.1 in locally installed gems")
    expect(err).to_not include("Your bundle is locked to myrack (0.9.1) from")
    expect(err).to_not include("If you haven't changed sources, that means the author of myrack (0.9.1) has removed it.")
    expect(err).to_not include("You'll need to update your bundle to a different version of myrack (0.9.1) that hasn't been removed in order to install.")

    # Check error message is still correct when multiple platforms are locked
    lockfile lockfile.gsub(/PLATFORMS\n  #{lockfile_platforms}/m, "PLATFORMS\n  #{lockfile_platforms("ruby")}")

    bundle :list, raise_on_error: false
    expect(err).to include("Could not find myrack-0.9.1 in locally installed gems")
  end

  it "does not suggest the author has yanked the gem when using more than one gem, but shows all gems that couldn't be found in the source" do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack", "0.9.1"
      gem "myrack_middleware", "1.0"
    G

    lockfile <<-L
      GEM
        remote: https://gem.repo1
        specs:
          myrack (0.9.1)
          myrack_middleware (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        myrack (= 0.9.1)
        myrack_middleware (1.0)
    L

    bundle :list, raise_on_error: false

    expect(err).to include("Could not find myrack-0.9.1, myrack_middleware-1.0 in locally installed gems")
    expect(err).to include("Install missing gems with `bundle install`.")
    expect(err).to_not include("Your bundle is locked to myrack (0.9.1) from")
    expect(err).to_not include("If you haven't changed sources, that means the author of myrack (0.9.1) has removed it.")
    expect(err).to_not include("You'll need to update your bundle to a different version of myrack (0.9.1) that hasn't been removed in order to install.")
  end
end
