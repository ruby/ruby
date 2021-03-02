# frozen_string_literal: true

RSpec.describe "bundle install across platforms" do
  it "maintains the same lockfile if all gems are compatible across platforms" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          rack (0.9.1)

      PLATFORMS
        #{not_local}

      DEPENDENCIES
        rack
    G

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rack"
    G

    expect(the_bundle).to include_gems "rack 0.9.1"
  end

  it "pulls in the correct platform specific gem" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}
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
      source "#{file_uri_for(gem_repo1)}"

      gem "platform_specific"
    G

    expect(the_bundle).to include_gems "platform_specific 1.0 JAVA"
  end

  it "pulls the pure ruby version on jruby if the java platform is not present in the lockfile and bundler is run in frozen mode", :jruby do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}
        specs:
          platform_specific (1.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        platform_specific
    G

    bundle "config set --local frozen true"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "platform_specific"
    G

    expect(the_bundle).to include_gems "platform_specific 1.0 RUBY"
  end

  it "works with gems that have different dependencies" do
    simulate_platform "java"
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "nokogiri"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2 JAVA", "weakling 0.0.3"

    simulate_new_machine

    simulate_platform "ruby"
    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
    expect(the_bundle).not_to include_gems "weakling"

    simulate_platform "java"
    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2 JAVA", "weakling 0.0.3"
  end

  it "does not keep unneeded platforms for gems that are used" do
    build_repo4 do
      build_gem "empyrean", "0.1.0"
      build_gem "coderay", "1.1.2"
      build_gem "method_source", "0.9.0"
      build_gem("spoon", "0.0.6") {|s| s.add_runtime_dependency "ffi" }
      build_gem "pry", "0.11.3" do |s|
        s.platform = "java"
        s.add_runtime_dependency "coderay", "~> 1.1.0"
        s.add_runtime_dependency "method_source", "~> 0.9.0"
        s.add_runtime_dependency "spoon", "~> 0.0"
      end
      build_gem "pry", "0.11.3" do |s|
        s.add_runtime_dependency "coderay", "~> 1.1.0"
        s.add_runtime_dependency "method_source", "~> 0.9.0"
      end
      build_gem("ffi", "1.9.23") {|s| s.platform = "java" }
      build_gem("ffi", "1.9.23")
    end

    simulate_platform java

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "empyrean", "0.1.0"
      gem "pry"
    G

    lockfile_should_be <<-L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          coderay (1.1.2)
          empyrean (0.1.0)
          ffi (1.9.23-java)
          method_source (0.9.0)
          pry (0.11.3-java)
            coderay (~> 1.1.0)
            method_source (~> 0.9.0)
            spoon (~> 0.0)
          spoon (0.0.6)
            ffi

      PLATFORMS
        java

      DEPENDENCIES
        empyrean (= 0.1.0)
        pry

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --add-platform ruby"

    good_lockfile = strip_whitespace(<<-L)
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          coderay (1.1.2)
          empyrean (0.1.0)
          ffi (1.9.23-java)
          method_source (0.9.0)
          pry (0.11.3)
            coderay (~> 1.1.0)
            method_source (~> 0.9.0)
          pry (0.11.3-java)
            coderay (~> 1.1.0)
            method_source (~> 0.9.0)
            spoon (~> 0.0)
          spoon (0.0.6)
            ffi

      PLATFORMS
        java
        ruby

      DEPENDENCIES
        empyrean (= 0.1.0)
        pry

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    lockfile_should_be good_lockfile

    bad_lockfile = strip_whitespace <<-L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          coderay (1.1.2)
          empyrean (0.1.0)
          ffi (1.9.23)
          ffi (1.9.23-java)
          method_source (0.9.0)
          pry (0.11.3)
            coderay (~> 1.1.0)
            method_source (~> 0.9.0)
          pry (0.11.3-java)
            coderay (~> 1.1.0)
            method_source (~> 0.9.0)
            spoon (~> 0.0)
          spoon (0.0.6)
            ffi

      PLATFORMS
        java
        ruby

      DEPENDENCIES
        empyrean (= 0.1.0)
        pry

      BUNDLED WITH
        #{Bundler::VERSION}
    L

    aggregate_failures do
      lockfile bad_lockfile
      bundle :install
      lockfile_should_be good_lockfile

      lockfile bad_lockfile
      bundle :update, :all => true
      lockfile_should_be good_lockfile

      lockfile bad_lockfile
      bundle "update ffi"
      lockfile_should_be good_lockfile

      lockfile bad_lockfile
      bundle "update empyrean"
      lockfile_should_be good_lockfile

      lockfile bad_lockfile
      bundle :lock
      lockfile_should_be good_lockfile
    end
  end

  it "works with gems with platform-specific dependency having different requirements order" do
    simulate_platform x64_mac

    update_repo2 do
      build_gem "fspath", "3"
      build_gem "image_optim_pack", "1.2.3" do |s|
        s.add_runtime_dependency "fspath", ">= 2.1", "< 4"
      end
      build_gem "image_optim_pack", "1.2.3" do |s|
        s.platform = "universal-darwin"
        s.add_runtime_dependency "fspath", "< 4", ">= 2.1"
      end
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
    G

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"

      gem "image_optim_pack"
    G

    expect(err).not_to include "Unable to use the platform-specific"

    expect(the_bundle).to include_gem "image_optim_pack 1.2.3 universal-darwin"
  end

  it "fetches gems again after changing the version of Ruby" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rack", "1.0.0"
    G

    bundle "config --local path vendor/bundle"
    bundle :install

    FileUtils.mv(vendored_gems, bundled_app("vendor/bundle", Gem.ruby_engine, "1.8"))

    bundle :install
    expect(vendored_gems("gems/rack-1.0.0")).to exist
  end

  it "keeps existing platforms when installing with force_ruby_platform" do
    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          platform_specific (1.0-java)

      PLATFORMS
        java

      DEPENDENCIES
        platform_specific
    G

    bundle "config set --local force_ruby_platform true"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "platform_specific"
    G

    expect(the_bundle).to include_gem "platform_specific 1.0 RUBY"

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          platform_specific (1.0)
          platform_specific (1.0-java)

      PLATFORMS
        java
        ruby

      DEPENDENCIES
        platform_specific

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end
end

RSpec.describe "bundle install with platform conditionals" do
  it "installs gems tagged w/ the current platforms" do
    skip "platform issues" if Gem.win_platform?

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      platforms :#{local_tag} do
        gem "nokogiri"
      end
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "does not install gems tagged w/ another platforms" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
      platforms :#{not_local_tag} do
        gem "nokogiri"
      end
    G

    expect(the_bundle).to include_gems "rack 1.0"
    expect(the_bundle).not_to include_gems "nokogiri 1.4.2"
  end

  it "installs gems tagged w/ the current platforms inline" do
    skip "platform issues" if Gem.win_platform?

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "nokogiri", :platforms => :#{local_tag}
    G
    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "does not install gems tagged w/ another platforms inline" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
      gem "nokogiri", :platforms => :#{not_local_tag}
    G
    expect(the_bundle).to include_gems "rack 1.0"
    expect(the_bundle).not_to include_gems "nokogiri 1.4.2"
  end

  it "installs gems tagged w/ the current platform inline" do
    skip "platform issues" if Gem.win_platform?

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "nokogiri", :platform => :#{local_tag}
    G
    expect(the_bundle).to include_gems "nokogiri 1.4.2"
  end

  it "doesn't install gems tagged w/ another platform inline" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
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

    bundle :list
  end

  it "does not attempt to install gems from :rbx when using --local" do
    simulate_platform "ruby"

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "some_gem", :platform => :rbx
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "does not attempt to install gems from other rubies when using --local" do
    simulate_platform "ruby"
    other_ruby_version_tag = RUBY_VERSION =~ /^1\.8/ ? :ruby_19 : :ruby_18

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "some_gem", platform: :#{other_ruby_version_tag}
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "does not print a warning when a dependency is unused on a platform different from the current one" do
    simulate_platform "ruby"

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rack", :platform => [:mingw, :mswin, :x64_mingw, :jruby]
    G

    bundle "install"

    expect(err).to be_empty

    lockfile_should_be <<-L
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
        rack

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end
end

RSpec.describe "when a gem has no architecture" do
  it "still installs correctly" do
    simulate_platform mswin

    build_repo2 do
      # The rcov gem is platform mswin32, but has no arch
      build_gem "rcov" do |s|
        s.platform = Gem::Platform.new([nil, "mswin32", nil])
        s.write "lib/rcov.rb", "RCOV = '1.0.0'"
      end
    end

    gemfile <<-G
      # Try to install gem with nil arch
      source "http://localgemserver.test/"
      gem "rcov"
    G

    bundle :install, :artifice => "windows", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
    expect(the_bundle).to include_gems "rcov 1.0.0"
  end
end
