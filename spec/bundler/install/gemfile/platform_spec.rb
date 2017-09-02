# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundle install across platforms" do
  it "maintains the same lockfile if all gems are compatible across platforms" do
    lockfile <<-G
      GEM
        remote: file:#{gem_repo1}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{not_local}

      DEPENDENCIES
        rack
    G

    install_gemfile <<-G
      source "file://#{gem_repo1}"

      gem "rack"
    G

    expect(the_bundle).to include_gems "rack 0.9.1"
  end

  it "pulls in the correct platform specific gem" do
    lockfile <<-G
      GEM
        remote: file:#{gem_repo1}
        specs:
          platform_specific (1.0)
          platform_specific (1.0-java)
          platform_specific (1.0-x86-mswin32)

      PLATFORMS
        ruby

      DEPENDENCIES
        platform_specific
    G

    simulate_platform "java"
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      gem "platform_specific"
    G

    expect(the_bundle).to include_gems "platform_specific 1.0 JAVA"
  end

  it "works with gems that have different dependencies" do
    simulate_platform "java"
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      gem "nokogiri"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2 JAVA", "weakling 0.0.3"

    simulate_new_machine

    simulate_platform "ruby"
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      gem "nokogiri"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
    expect(the_bundle).not_to include_gems "weakling"
  end

  it "works the other way with gems that have different dependencies" do
    simulate_platform "ruby"
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      gem "nokogiri"
    G

    simulate_platform "java"
    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2 JAVA", "weakling 0.0.3"
  end

  it "works with gems that have extra platform-specific runtime dependencies" do
    simulate_platform x64_mac

    update_repo2 do
      build_gem "facter", "2.4.6"
      build_gem "facter", "2.4.6" do |s|
        s.platform = "universal-darwin"
        s.add_runtime_dependency "CFPropertyList"
      end
      build_gem "CFPropertyList"
    end

    install_gemfile! <<-G
      source "file://#{gem_repo2}"

      gem "facter"
    G

    expect(out).to include "Unable to use the platform-specific (universal-darwin) version of facter (2.4.6) " \
      "because it has different dependencies from the ruby version. " \
      "To use the platform-specific version of the gem, run `bundle config specific_platform true` and install again."

    expect(the_bundle).to include_gem "facter 2.4.6"
    expect(the_bundle).not_to include_gem "CFPropertyList"
  end

  it "fetches gems again after changing the version of Ruby" do
    gemfile <<-G
      source "file://#{gem_repo1}"

      gem "rack", "1.0.0"
    G

    bundle "install --path vendor/bundle"

    new_version = Gem::ConfigMap[:ruby_version] == "1.8" ? "1.9.1" : "1.8"
    FileUtils.mv(vendored_gems, bundled_app("vendor/bundle", Gem.ruby_engine, new_version))

    bundle "install --path vendor/bundle"
    expect(vendored_gems("gems/rack-1.0.0")).to exist
  end
end

RSpec.describe "bundle install with platform conditionals" do
  it "installs gems tagged w/ the current platforms" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      platforms :#{local_tag} do
        gem "nokogiri"
      end
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "does not install gems tagged w/ another platforms" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      platforms :#{not_local_tag} do
        gem "nokogiri"
      end
    G

    expect(the_bundle).to include_gems "rack 1.0"
    expect(the_bundle).not_to include_gems "nokogiri 1.4.2"
  end

  it "installs gems tagged w/ the current platforms inline" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "nokogiri", :platforms => :#{local_tag}
    G
    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "does not install gems tagged w/ another platforms inline" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "nokogiri", :platforms => :#{not_local_tag}
    G
    expect(the_bundle).to include_gems "rack 1.0"
    expect(the_bundle).not_to include_gems "nokogiri 1.4.2"
  end

  it "installs gems tagged w/ the current platform inline" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "nokogiri", :platform => :#{local_tag}
    G
    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "doesn't install gems tagged w/ another platform inline" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "nokogiri", :platform => :#{not_local_tag}
    G
    expect(the_bundle).not_to include_gems "nokogiri 1.4.2"
  end

  it "does not blow up on sources with all platform-excluded specs" do
    build_git "foo"

    install_gemfile <<-G
      platform :#{not_local_tag} do
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end
    G

    bundle :show
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "does not attempt to install gems from :rbx when using --local" do
    simulate_platform "ruby"
    simulate_ruby_engine "ruby"

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "some_gem", :platform => :rbx
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "does not attempt to install gems from other rubies when using --local" do
    simulate_platform "ruby"
    simulate_ruby_engine "ruby"
    other_ruby_version_tag = RUBY_VERSION =~ /^1\.8/ ? :ruby_19 : :ruby_18

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "some_gem", platform: :#{other_ruby_version_tag}
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "prints a helpful warning when a dependency is unused on any platform" do
    simulate_platform "ruby"
    simulate_ruby_engine "ruby"

    gemfile <<-G
      source "file://#{gem_repo1}"

      gem "rack", :platform => [:mingw, :mswin, :x64_mingw, :jruby]
    G

    bundle! "install"

    expect(out).to include <<-O.strip
The dependency #{Gem::Dependency.new("rack", ">= 0")} will be unused by any of the platforms Bundler is installing for. Bundler is installing for ruby but the dependency is only for x86-mingw32, x86-mswin32, x64-mingw32, java. To add those platforms to the bundle, run `bundle lock --add-platform x86-mingw32 x86-mswin32 x64-mingw32 java`.
    O
  end
end

RSpec.describe "when a gem has no architecture" do
  it "still installs correctly" do
    simulate_platform mswin

    gemfile <<-G
      # Try to install gem with nil arch
      source "http://localgemserver.test/"
      gem "rcov"
    G

    bundle :install, :artifice => "windows"
    expect(the_bundle).to include_gems "rcov 1.0.0"
  end
end
