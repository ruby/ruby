# frozen_string_literal: true

RSpec.describe "Bundler.setup with multi platform stuff" do
  it "raises a friendly error when gems are missing locally" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
    G

    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          rack (1.0)

      PLATFORMS
        #{local_tag}

      DEPENDENCIES
        rack
    G

    ruby <<-R
      begin
        require 'bundler'
        Bundler.setup
      rescue Bundler::GemNotFound => e
        puts "WIN"
      end
    R

    expect(out).to eq("WIN")
  end

  it "will resolve correctly on the current platform when the lockfile was targeted for a different one" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          nokogiri (1.4.2-java)
            weakling (= 0.0.3)
          weakling (0.0.3)

      PLATFORMS
        java

      DEPENDENCIES
        nokogiri
    G

    simulate_platform "x86-darwin-10"
    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "nokogiri"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "will add the resolve for the current platform" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          nokogiri (1.4.2-java)
            weakling (= 0.0.3)
          weakling (0.0.3)

      PLATFORMS
        java

      DEPENDENCIES
        nokogiri
    G

    simulate_platform "x86-darwin-100"

    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "nokogiri"
      gem "platform_specific"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 x86-darwin-100"
  end

  it "allows specifying only-ruby-platform" do
    simulate_platform "java"

    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "nokogiri"
      gem "platform_specific"
    G

    bundle! "config set force_ruby_platform true"

    bundle! "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2", "platform_specific 1.0 RUBY"
  end

  it "allows specifying only-ruby-platform on windows with dependency platforms" do
    simulate_windows do
      install_gemfile! <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "nokogiri", :platforms => [:mingw, :mswin, :x64_mingw, :jruby]
        gem "platform_specific"
      G

      bundle! "config set force_ruby_platform true"

      bundle! "install"

      expect(the_bundle).to include_gems "platform_specific 1.0 RUBY"
    end
  end

  it "allows specifying only-ruby-platform on windows with gemspec dependency" do
    build_lib("foo", "1.0", :path => ".") do |s|
      s.add_dependency "rack"
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec
    G
    bundle! :lock

    simulate_windows do
      bundle! "config set force_ruby_platform true"
      bundle! "install"

      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  it "recovers when the lockfile is missing a platform-specific gem" do
    build_repo2 do
      build_gem "requires_platform_specific" do |s|
        s.add_dependency "platform_specific"
      end
    end
    simulate_windows x64_mingw do
      lockfile <<-L
        GEM
          remote: #{file_uri_for(gem_repo2)}/
          specs:
            platform_specific (1.0-x86-mingw32)
            requires_platform_specific (1.0)
              platform_specific

        PLATFORMS
          x64-mingw32
          x86-mingw32

        DEPENDENCIES
          requires_platform_specific
      L

      install_gemfile! <<-G, :verbose => true
        source "#{file_uri_for(gem_repo2)}"
        gem "requires_platform_specific"
      G

      expect(the_bundle).to include_gem "platform_specific 1.0 x64-mingw32"
    end
  end
end
