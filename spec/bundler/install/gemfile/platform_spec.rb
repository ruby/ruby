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

  it "pulls the pure ruby version on jruby if the java platform is not present in the lockfile and bundler is run in frozen mode", :jruby_only do
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

  context "on universal Rubies" do
    before do
      build_repo4 do
        build_gem "darwin_single_arch" do |s|
          s.platform = "ruby"
          s.write "lib/darwin_single_arch.rb", "DARWIN_SINGLE_ARCH = '1.0 RUBY'"
        end
        build_gem "darwin_single_arch" do |s|
          s.platform = "arm64-darwin"
          s.write "lib/darwin_single_arch.rb", "DARWIN_SINGLE_ARCH = '1.0 arm64-darwin'"
        end
        build_gem "darwin_single_arch" do |s|
          s.platform = "x86_64-darwin"
          s.write "lib/darwin_single_arch.rb", "DARWIN_SINGLE_ARCH = '1.0 x86_64-darwin'"
        end
      end
    end

    it "pulls in the correct architecture gem" do
      lockfile <<-G
        GEM
          remote: #{file_uri_for(gem_repo4)}
          specs:
            darwin_single_arch (1.0)
            darwin_single_arch (1.0-arm64-darwin)
            darwin_single_arch (1.0-x86_64-darwin)

        PLATFORMS
          ruby

        DEPENDENCIES
          darwin_single_arch
      G

      simulate_platform "universal-darwin-21"
      simulate_ruby_platform "universal.x86_64-darwin21" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"

          gem "darwin_single_arch"
        G

        expect(the_bundle).to include_gems "darwin_single_arch 1.0 x86_64-darwin"
      end
    end

    it "pulls in the correct architecture gem on arm64e macOS Ruby" do
      lockfile <<-G
        GEM
          remote: #{file_uri_for(gem_repo4)}
          specs:
            darwin_single_arch (1.0)
            darwin_single_arch (1.0-arm64-darwin)
            darwin_single_arch (1.0-x86_64-darwin)

        PLATFORMS
          ruby

        DEPENDENCIES
          darwin_single_arch
      G

      simulate_platform "universal-darwin-21"
      simulate_ruby_platform "universal.arm64e-darwin21" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo4)}"

          gem "darwin_single_arch"
        G

        expect(the_bundle).to include_gems "darwin_single_arch 1.0 arm64-darwin"
      end
    end
  end

  it "works with gems that have different dependencies" do
    simulate_platform "java"
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "nokogiri"
    G

    expect(the_bundle).to include_gems "nokogiri 1.4.2 JAVA", "weakling 0.0.3"

    simulate_new_machine
    bundle "config set --local force_ruby_platform true"
    bundle "install"

    expect(the_bundle).to include_gems "nokogiri 1.4.2"
    expect(the_bundle).not_to include_gems "weakling"

    simulate_new_machine
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

    expect(lockfile).to eq <<~L
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

      CHECKSUMS
        #{checksum_for_repo_gem gem_repo4, "coderay", "1.1.2"}
        #{checksum_for_repo_gem gem_repo4, "empyrean", "0.1.0"}
        #{checksum_for_repo_gem gem_repo4, "ffi", "1.9.23", "java"}
        #{checksum_for_repo_gem gem_repo4, "method_source", "0.9.0"}
        #{checksum_for_repo_gem gem_repo4, "pry", "0.11.3", "java"}
        #{checksum_for_repo_gem gem_repo4, "spoon", "0.0.6"}

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --add-platform ruby"

    good_lockfile = <<~L
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

      CHECKSUMS
        #{checksum_for_repo_gem gem_repo4, "coderay", "1.1.2"}
        #{checksum_for_repo_gem gem_repo4, "empyrean", "0.1.0"}
        #{checksum_for_repo_gem gem_repo4, "ffi", "1.9.23", "java"}
        #{checksum_for_repo_gem gem_repo4, "method_source", "0.9.0"}
        pry (0.11.3)
        #{checksum_for_repo_gem gem_repo4, "pry", "0.11.3", "java"}
        #{checksum_for_repo_gem gem_repo4, "spoon", "0.0.6"}

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    expect(lockfile).to eq good_lockfile

    bad_lockfile = <<~L
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

      CHECKSUMS
        #{checksum_for_repo_gem gem_repo4, "coderay", "1.1.2"}
        #{checksum_for_repo_gem gem_repo4, "empyrean", "0.1.0"}
        #{checksum_for_repo_gem gem_repo4, "ffi", "1.9.23", "java"}
        #{checksum_for_repo_gem gem_repo4, "method_source", "0.9.0"}
        #{checksum_for_repo_gem gem_repo4, "pry", "0.11.3", "java"}
        #{checksum_for_repo_gem gem_repo4, "spoon", "0.0.6"}

      BUNDLED WITH
         1.16.1
    L

    aggregate_failures do
      lockfile bad_lockfile
      bundle :install, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      expect(lockfile).to eq good_lockfile

      lockfile bad_lockfile
      bundle :update, :all => true, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      expect(lockfile).to eq good_lockfile

      lockfile bad_lockfile
      bundle "update ffi", :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      expect(lockfile).to eq good_lockfile

      lockfile bad_lockfile
      bundle "update empyrean", :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      expect(lockfile).to eq good_lockfile

      lockfile bad_lockfile
      bundle :lock, :env => { "BUNDLER_VERSION" => Bundler::VERSION }
      expect(lockfile).to eq good_lockfile
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

    bundle "config set --local path vendor/bundle"
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

    expect(lockfile).to eq <<~G
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

      CHECKSUMS
        #{checksum_for_repo_gem(gem_repo1, "platform_specific", "1.0")}
        #{checksum_for_repo_gem(gem_repo1, "platform_specific", "1.0", "java", :empty => true)}

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end
end

RSpec.describe "bundle install with platform conditionals" do
  it "installs gems tagged w/ the current platforms" do
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

  it "installs gems tagged w/ another platform but also dependent on the current one transitively" do
    build_repo4 do
      build_gem "activesupport", "6.1.4.1" do |s|
        s.add_dependency "tzinfo", "~> 2.0"
      end

      build_gem "tzinfo", "2.0.4"
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "activesupport"

      platforms :#{not_local_tag} do
        gem "tzinfo", "~> 1.2"
      end
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          activesupport (6.1.4.1)
            tzinfo (~> 2.0)
          tzinfo (2.0.4)

      PLATFORMS
        #{local_platform}

      DEPENDENCIES
        activesupport
        tzinfo (~> 1.2)

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install --verbose"

    expect(the_bundle).to include_gems "tzinfo 2.0.4"
  end

  it "installs gems tagged w/ the current platforms inline" do
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
      source "#{file_uri_for(gem_repo1)}"
      platform :#{not_local_tag} do
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end
    G

    bundle :list
  end

  it "does not attempt to install gems from :rbx when using --local" do
    bundle "config set --local force_ruby_platform true"

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "some_gem", :platform => :rbx
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "does not attempt to install gems from other rubies when using --local" do
    bundle "config set --local force_ruby_platform true"
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "some_gem", platform: :ruby_22
    G

    bundle "install --local"
    expect(out).not_to match(/Could not find gem 'some_gem/)
  end

  it "does not print a warning when a dependency is unused on a platform different from the current one" do
    bundle "config set --local force_ruby_platform true"

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "rack", :platform => [:windows, :mswin, :mswin64, :mingw, :x64_mingw, :jruby]
    G

    bundle "install"

    expect(err).to be_empty

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES
        rack

      CHECKSUMS

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "resolves fine when a dependency is unused on a platform different from the current one, but reintroduced transitively" do
    bundle "config set --local force_ruby_platform true"

    build_repo4 do
      build_gem "listen", "3.7.1" do |s|
        s.add_dependency "ffi"
      end

      build_gem "ffi", "1.15.5"
    end

    install_gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "listen"
      gem "ffi", :platform => :windows
    G
    expect(err).to be_empty
  end
end

RSpec.describe "when a gem has no architecture" do
  it "still installs correctly" do
    simulate_platform x86_mswin32

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
