# frozen_string_literal: true

RSpec.describe "bundle lock" do
  let(:repo) { gem_repo1 }

  before :each do
    gemfile <<-G
      source "#{file_uri_for(repo)}"
      gem "rails"
      gem "weakling"
      gem "foo"
    G

    checksums = checksums_section_when_existing do |c|
      c.checksum repo, "actionmailer", "2.3.2"
      c.checksum repo, "actionpack", "2.3.2"
      c.checksum repo, "activerecord", "2.3.2"
      c.checksum repo, "activeresource", "2.3.2"
      c.checksum repo, "activesupport", "2.3.2"
      c.checksum repo, "foo", "1.0"
      c.checksum repo, "rails", "2.3.2"
      c.checksum repo, "rake", rake_version
      c.checksum repo, "weakling", "0.0.3"
    end

    @lockfile = <<~L
      GEM
        remote: #{file_uri_for(repo)}/
        specs:
          actionmailer (2.3.2)
            activesupport (= 2.3.2)
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activerecord (2.3.2)
            activesupport (= 2.3.2)
          activeresource (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          foo (1.0)
          rails (2.3.2)
            actionmailer (= 2.3.2)
            actionpack (= 2.3.2)
            activerecord (= 2.3.2)
            activeresource (= 2.3.2)
            rake (= #{rake_version})
          rake (#{rake_version})
          weakling (0.0.3)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo
        rails
        weakling
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "prints a lockfile when there is no existing lockfile with --print" do
    bundle "lock --print"

    expect(out).to eq(@lockfile.chomp)
  end

  it "prints a lockfile when there is an existing lockfile with --print" do
    lockfile remove_checksums_section_from_lockfile(@lockfile)

    bundle "lock --print"

    expect(out).to eq(remove_checksums_section_from_lockfile(@lockfile).chomp)
  end

  it "prints a lockfile when there is an existing checksums lockfile with --print" do
    lockfile @lockfile

    bundle "lock --print"

    expect(out).to eq(@lockfile.chomp)
  end

  it "writes a lockfile when there is no existing lockfile" do
    bundle "lock"

    expect(read_lockfile).to eq(@lockfile)
  end

  it "prints a lockfile without fetching new checksums if the existing lockfile had no checksums" do
    lockfile remove_checksums_from_lockfile(@lockfile)

    bundle "lock --print"

    expect(out).to eq(remove_checksums_from_lockfile(@lockfile).chomp)
  end

  it "touches the lockfile when there is an existing lockfile that does not need changes" do
    lockfile @lockfile

    expect do
      bundle "lock"
    end.to change { bundled_app_lock.mtime }
  end

  it "does not touch lockfile with --print" do
    lockfile @lockfile

    expect do
      bundle "lock --print"
    end.not_to change { bundled_app_lock.mtime }
  end

  it "writes a lockfile when there is an outdated lockfile using --update" do
    lockfile remove_checksums_from_lockfile(@lockfile.gsub("2.3.2", "2.3.1"), " (2.3.1)")

    bundle "lock --update"

    expect(read_lockfile).to eq(remove_checksums_from_lockfile(@lockfile))
  end

  it "writes a lockfile with checksums on --update when checksums exist" do
    lockfile @lockfile.gsub("2.3.2", "2.3.1")

    bundle "lock --update"

    expect(read_lockfile).to eq(@lockfile)
  end

  it "writes a lockfile when there is an outdated lockfile and bundle is frozen" do
    lockfile @lockfile.gsub("2.3.2", "2.3.1")

    bundle "lock --update", env: { "BUNDLE_FROZEN" => "true" }

    expect(read_lockfile).to eq(@lockfile)
  end

  it "does not fetch remote specs when using the --local option" do
    bundle "lock --update --local", raise_on_error: false

    expect(err).to match(/locally installed gems/)
  end

  it "does not fetch remote checksums with --local" do
    lockfile remove_checksums_from_lockfile(@lockfile)

    bundle "lock --print --local"

    # No checksums because --local prevents fetching them
    expect(out).to eq(remove_checksums_from_lockfile(@lockfile).chomp)
  end

  it "works with --gemfile flag" do
    create_file "CustomGemfile", <<-G
      source "#{file_uri_for(repo)}"
      gem "foo"
    G
    checksums = checksums_section_when_existing do |c|
      c.no_checksum "foo", "1.0"
    end

    lockfile = <<~L
      GEM
        remote: #{file_uri_for(repo)}/
        specs:
          foo (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L
    bundle "lock --gemfile CustomGemfile"

    expect(out).to match(/Writing lockfile to.+CustomGemfile\.lock/)
    expect(read_lockfile("CustomGemfile.lock")).to eq(lockfile)
    expect { read_lockfile }.to raise_error(Errno::ENOENT)
  end

  it "writes to a custom location using --lockfile" do
    bundle "lock --lockfile=lock"

    expect(out).to match(/Writing lockfile to.+lock/)
    expect(read_lockfile("lock")).to eq(remove_checksums_from_lockfile(@lockfile))
    expect { read_lockfile }.to raise_error(Errno::ENOENT)
  end

  it "writes to custom location using --lockfile when a default lockfile is present" do
    bundle "install"
    bundle "lock --lockfile=lock"

    checksums = checksums_section_when_existing do |c|
      c.checksum repo, "actionmailer", "2.3.2"
      c.checksum repo, "actionpack", "2.3.2"
      c.checksum repo, "activerecord", "2.3.2"
      c.checksum repo, "activeresource", "2.3.2"
      c.checksum repo, "activesupport", "2.3.2"
      c.checksum repo, "foo", "1.0"
      c.checksum repo, "rails", "2.3.2"
      c.checksum repo, "rake", rake_version
      c.checksum repo, "weakling", "0.0.3"
    end

    lockfile = <<~L
      GEM
        remote: #{file_uri_for(repo)}/
        specs:
          actionmailer (2.3.2)
            activesupport (= 2.3.2)
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activerecord (2.3.2)
            activesupport (= 2.3.2)
          activeresource (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          foo (1.0)
          rails (2.3.2)
            actionmailer (= 2.3.2)
            actionpack (= 2.3.2)
            activerecord (= 2.3.2)
            activeresource (= 2.3.2)
            rake (= #{rake_version})
          rake (#{rake_version})
          weakling (0.0.3)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo
        rails
        weakling
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    expect(out).to match(/Writing lockfile to.+lock/)
    expect(read_lockfile("lock")).to eq(lockfile)
  end

  it "update specific gems using --update" do
    lockfile @lockfile.gsub("2.3.2", "2.3.1").gsub(rake_version, "10.0.1")

    bundle "lock --update rails rake"

    expect(read_lockfile).to eq(remove_checksums_from_lockfile(@lockfile, "(2.3.2)", "(#{rake_version})"))
  end

  it "updates specific gems using --update, even if that requires unlocking other top level gems" do
    build_repo4 do
      build_gem "prism", "0.15.1"
      build_gem "prism", "0.24.0"

      build_gem "ruby-lsp", "0.12.0" do |s|
        s.add_dependency "prism", "< 0.24.0"
      end

      build_gem "ruby-lsp", "0.16.1" do |s|
        s.add_dependency "prism", ">= 0.24.0"
      end

      build_gem "tapioca", "0.11.10" do |s|
        s.add_dependency "prism", "< 0.24.0"
      end

      build_gem "tapioca", "0.13.1" do |s|
        s.add_dependency "prism", ">= 0.24.0"
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "tapioca"
      gem "ruby-lsp"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}
        specs:
          prism (0.15.1)
          ruby-lsp (0.12.0)
            prism (< 0.24.0)
          tapioca (0.11.10)
            prism (< 0.24.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        ruby-lsp
        tapioca

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --update tapioca --verbose"

    expect(lockfile).to include("tapioca (0.13.1)")
  end

  it "updates specific gems using --update, even if that requires unlocking other top level gems, but only as few as possible" do
    build_repo4 do
      build_gem "prism", "0.15.1"
      build_gem "prism", "0.24.0"

      build_gem "ruby-lsp", "0.12.0" do |s|
        s.add_dependency "prism", "< 0.24.0"
      end

      build_gem "ruby-lsp", "0.16.1" do |s|
        s.add_dependency "prism", ">= 0.24.0"
      end

      build_gem "tapioca", "0.11.10" do |s|
        s.add_dependency "prism", "< 0.24.0"
      end

      build_gem "tapioca", "0.13.1" do |s|
        s.add_dependency "prism", ">= 0.24.0"
      end

      build_gem "other-prism-dependent", "1.0.0" do |s|
        s.add_dependency "prism", ">= 0.15.1"
      end

      build_gem "other-prism-dependent", "1.1.0" do |s|
        s.add_dependency "prism", ">= 0.15.1"
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "tapioca"
      gem "ruby-lsp"
      gem "other-prism-dependent"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}
        specs:
          other-prism-dependent (1.0.0)
            prism (>= 0.15.1)
          prism (0.15.1)
          ruby-lsp (0.12.0)
            prism (< 0.24.0)
          tapioca (0.11.10)
            prism (< 0.24.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        ruby-lsp
        tapioca

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --update tapioca"

    expect(lockfile).to include("tapioca (0.13.1)")
    expect(lockfile).to include("other-prism-dependent (1.0.0)")
  end

  it "preserves unknown checksum algorithms" do
    lockfile @lockfile.gsub(/(sha256=[a-f0-9]+)$/, "constant=true,\\1,xyz=123")

    previous_lockfile = read_lockfile

    bundle "lock"

    expect(read_lockfile).to eq(previous_lockfile)
  end

  it "does not unlock git sources when only uri shape changes" do
    build_git("foo")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => "#{file_uri_for(lib_path("foo-1.0"))}"
    G

    # Change uri format to end with "/" and reinstall
    install_gemfile <<-G, verbose: true
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :git => "#{file_uri_for(lib_path("foo-1.0"))}/"
    G

    expect(out).to include("using resolution from the lockfile")
    expect(out).not_to include("re-resolving dependencies because the list of sources changed")
  end

  it "updates specific gems using --update using the locked revision of unrelated git gems for resolving" do
    ref = build_git("foo").ref_for("HEAD")

    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rake"
      gem "foo", :git => "#{file_uri_for(lib_path("foo-1.0"))}", :branch => "deadbeef"
    G

    lockfile <<~L
      GIT
        remote: #{file_uri_for(lib_path("foo-1.0"))}
        revision: #{ref}
        branch: deadbeef
        specs:
          foo (1.0)

      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          rake (10.0.1)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo!
        rake

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --update rake --verbose"
    expect(out).to match(/Writing lockfile to.+lock/)
    expect(lockfile).to include("rake (#{rake_version})")
  end

  it "errors when updating a missing specific gems using --update" do
    lockfile @lockfile

    bundle "lock --update blahblah", raise_on_error: false
    expect(err).to eq("Could not find gem 'blahblah'.")

    expect(read_lockfile).to eq(@lockfile)
  end

  it "can lock without downloading gems" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "thin"
      gem "rack_middleware", :group => "test"
    G
    bundle "config set without test"
    bundle "config set path vendor/bundle"
    bundle "lock", verbose: true
    expect(bundled_app("vendor/bundle")).not_to exist
  end

  # see update_spec for more coverage on same options. logic is shared so it's not necessary
  # to repeat coverage here.
  context "conservative updates" do
    before do
      build_repo4 do
        build_gem "foo", %w[1.4.3 1.4.4] do |s|
          s.add_dependency "bar", "~> 2.0"
        end
        build_gem "foo", %w[1.4.5 1.5.0] do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "foo", %w[1.5.1] do |s|
          s.add_dependency "bar", "~> 3.0"
        end
        build_gem "foo", %w[2.0.0.pre] do |s|
          s.add_dependency "bar"
        end
        build_gem "bar", %w[2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 2.1.2.pre 3.0.0 3.1.0.pre 4.0.0.pre]
        build_gem "qux", %w[1.0.0 1.0.1 1.1.0 2.0.0]
      end

      # establish a lockfile set to 1.4.3
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo'
        gem 'qux'
      G

      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    end

    it "single gem updates dependent gem to minor" do
      bundle "lock --update foo --patch"

      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.4.5 bar-2.1.1 qux-1.0.0].sort)
    end

    it "minor preferred with strict" do
      bundle "lock --update --minor --strict"

      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.5.0 bar-2.1.1 qux-1.1.0].sort)
    end

    it "shows proper error when Gemfile changes forbid patch upgrades, and --patch --strict is given" do
      # force next minor via Gemfile
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo', '1.5.0'
        gem 'qux'
      G

      bundle "lock --update foo --patch --strict", raise_on_error: false

      expect(err).to include(
        "foo is locked to 1.4.3, while Gemfile is requesting foo (= 1.5.0). " \
        "--strict --patch was specified, but there are no patch level upgrades from 1.4.3 satisfying foo (= 1.5.0), so version solving has failed"
      )
    end

    context "pre" do
      it "defaults to major" do
        bundle "lock --update --pre"

        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-2.0.0.pre bar-4.0.0.pre qux-2.0.0].sort)
      end

      it "patch preferred" do
        bundle "lock --update --patch --pre"

        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.4.5 bar-2.1.2.pre qux-1.0.1].sort)
      end

      it "minor preferred" do
        bundle "lock --update --minor --pre"

        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.5.1 bar-3.1.0.pre qux-1.1.0].sort)
      end

      it "major preferred" do
        bundle "lock --update --major --pre"

        expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-2.0.0.pre bar-4.0.0.pre qux-2.0.0].sort)
      end
    end
  end

  context "conservative updates when minor update adds a new dependency" do
    before do
      build_repo4 do
        build_gem "sequel", "5.71.0"
        build_gem "sequel", "5.72.0" do |s|
          s.add_dependency "bigdecimal", ">= 0"
        end
        build_gem "bigdecimal", %w[1.4.4 99.1.4]
      end

      gemfile <<~G
        source "#{file_uri_for(gem_repo4)}"
        gem 'sequel'
      G

      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            sequel (5.71.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          sequel

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    end

    it "adds the latest version of the new dependency" do
      bundle "lock --minor --update sequel"

      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[sequel-5.72.0 bigdecimal-99.1.4].sort)
    end
  end

  it "updates the bundler version in the lockfile to the latest bundler version" do
    build_repo4 do
      build_gem "bundler", "55"
    end

    system_gems "bundler-55", gem_repo: gem_repo4

    install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "https://gems.repo4"
    G
    lockfile lockfile.sub(/(^\s*)#{Bundler::VERSION}($)/, '\11.0.0\2')

    bundle "lock --update --bundler --verbose", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
    expect(lockfile).to end_with("BUNDLED WITH\n   55\n")

    update_repo4 do
      build_gem "bundler", "99"
    end

    bundle "lock --update --bundler --verbose", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
    expect(lockfile).to end_with("BUNDLED WITH\n   99\n")
  end

  it "supports adding new platforms" do
    bundle "lock --add-platform java x86-mingw32"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(default_platform_list(java, x86_mingw32))
  end

  it "supports adding new platforms with force_ruby_platform = true" do
    lockfile <<-L
      GEM
        remote: #{file_uri_for(gem_repo1)}/
        specs:
          platform_specific (1.0)
          platform_specific (1.0-x86-64_linux)

      PLATFORMS
        ruby
        x86_64-linux

      DEPENDENCIES
        platform_specific
    L

    bundle "config set force_ruby_platform true"
    bundle "lock --add-platform java x86-mingw32"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to contain_exactly(rb, linux, java, x86_mingw32)
  end

  it "supports adding the `ruby` platform" do
    bundle "lock --add-platform ruby"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(default_platform_list("ruby"))
  end

  it "warns when adding an unknown platform" do
    bundle "lock --add-platform foobarbaz"
    expect(err).to include("The platform `foobarbaz` is unknown to RubyGems and adding it will likely lead to resolution errors")
  end

  it "allows removing platforms" do
    bundle "lock --add-platform java x86-mingw32"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(default_platform_list(java, x86_mingw32))

    bundle "lock --remove-platform java"

    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(default_platform_list(x86_mingw32))
  end

  it "also cleans up redundant platform gems when removing platforms" do
    build_repo4 do
      build_gem "nokogiri", "1.12.0"
      build_gem "nokogiri", "1.12.0" do |s|
        s.platform = "x86_64-darwin"
      end
    end

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo4, "nokogiri", "1.12.0"
      c.checksum gem_repo4, "nokogiri", "1.12.0", "x86_64-darwin"
    end

    simulate_platform "x86_64-darwin-22" do
      install_gemfile <<~G
        source "#{file_uri_for(gem_repo4)}"

        gem "nokogiri"
      G
    end

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          nokogiri (1.12.0)
          nokogiri (1.12.0-x86_64-darwin)

      PLATFORMS
        ruby
        x86_64-darwin

      DEPENDENCIES
        nokogiri
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L

    checksums.delete("nokogiri", Gem::Platform::RUBY)

    simulate_platform "x86_64-darwin-22" do
      bundle "lock --remove-platform ruby"
    end

    expect(lockfile).to eq <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          nokogiri (1.12.0-x86_64-darwin)

      PLATFORMS
        x86_64-darwin

      DEPENDENCIES
        nokogiri
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "errors when removing all platforms" do
    bundle "lock --remove-platform #{local_platform}", raise_on_error: false
    expect(err).to include("Removing all platforms from the bundle is not allowed")
  end

  # from https://github.com/rubygems/bundler/issues/4896
  it "properly adds platforms when platform requirements come from different dependencies" do
    build_repo4 do
      build_gem "ffi", "1.9.14"
      build_gem "ffi", "1.9.14" do |s|
        s.platform = x86_mingw32
      end

      build_gem "gssapi", "0.1"
      build_gem "gssapi", "0.2"
      build_gem "gssapi", "0.3"
      build_gem "gssapi", "1.2.0" do |s|
        s.add_dependency "ffi", ">= 1.0.1"
      end

      build_gem "mixlib-shellout", "2.2.6"
      build_gem "mixlib-shellout", "2.2.6" do |s|
        s.platform = "universal-mingw32"
        s.add_dependency "win32-process", "~> 0.8.2"
      end

      # we need all these versions to get the sorting the same as it would be
      # pulling from rubygems.org
      %w[0.8.3 0.8.2 0.8.1 0.8.0].each do |v|
        build_gem "win32-process", v do |s|
          s.add_dependency "ffi", ">= 1.0.0"
        end
      end
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "mixlib-shellout"
      gem "gssapi"
    G

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "ffi", "1.9.14", "x86-mingw32"
      c.no_checksum "gssapi", "1.2.0"
      c.no_checksum "mixlib-shellout", "2.2.6", "universal-mingw32"
      c.no_checksum "win32-process", "0.8.3"
    end

    simulate_platform(x86_mingw32) { bundle :lock }

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          ffi (1.9.14-x86-mingw32)
          gssapi (1.2.0)
            ffi (>= 1.0.1)
          mixlib-shellout (2.2.6-universal-mingw32)
            win32-process (~> 0.8.2)
          win32-process (0.8.3)
            ffi (>= 1.0.0)

      PLATFORMS
        x86-mingw32

      DEPENDENCIES
        gssapi
        mixlib-shellout
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G

    bundle "config set --local force_ruby_platform true"
    bundle :lock

    checksums.no_checksum "ffi", "1.9.14"
    checksums.no_checksum "mixlib-shellout", "2.2.6"

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          ffi (1.9.14)
          ffi (1.9.14-x86-mingw32)
          gssapi (1.2.0)
            ffi (>= 1.0.1)
          mixlib-shellout (2.2.6)
          mixlib-shellout (2.2.6-universal-mingw32)
            win32-process (~> 0.8.2)
          win32-process (0.8.3)
            ffi (>= 1.0.0)

      PLATFORMS
        ruby
        x86-mingw32

      DEPENDENCIES
        gssapi
        mixlib-shellout
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "doesn't crash when an update candidate doesn't have any matching platform" do
    build_repo4 do
      build_gem "libv8", "8.4.255.0"
      build_gem "libv8", "8.4.255.0" do |s|
        s.platform = "x86_64-darwin-19"
      end

      build_gem "libv8", "15.0.71.48.1beta2" do |s|
        s.platform = "x86_64-linux"
      end
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "libv8"
    G

    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          libv8 (8.4.255.0)
          libv8 (8.4.255.0-x86_64-darwin-19)

      PLATFORMS
        ruby
        x86_64-darwin-19

      DEPENDENCIES
        libv8

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    simulate_platform(Gem::Platform.new("x86_64-darwin-19")) { bundle "lock --update" }

    expect(out).to match(/Writing lockfile to.+Gemfile\.lock/)
  end

  it "adds all more specific candidates when they all have the same dependencies" do
    build_repo4 do
      build_gem "libv8", "8.4.255.0" do |s|
        s.platform = "x86_64-darwin-19"
      end

      build_gem "libv8", "8.4.255.0" do |s|
        s.platform = "x86_64-darwin-20"
      end
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "libv8"
    G

    simulate_platform(Gem::Platform.new("x86_64-darwin-19")) { bundle "lock" }

    checksums = checksums_section_when_existing do |c|
      c.no_checksum "libv8", "8.4.255.0", "x86_64-darwin-19"
      c.no_checksum "libv8", "8.4.255.0", "x86_64-darwin-20"
    end

    expect(lockfile).to eq <<~G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          libv8 (8.4.255.0-x86_64-darwin-19)
          libv8 (8.4.255.0-x86_64-darwin-20)

      PLATFORMS
        x86_64-darwin-19
        x86_64-darwin-20

      DEPENDENCIES
        libv8
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  it "respects the previous lockfile if it had a matching less specific platform already locked, and installs the best variant for each platform" do
    build_repo4 do
      build_gem "libv8", "8.4.255.0" do |s|
        s.platform = "x86_64-darwin-19"
      end

      build_gem "libv8", "8.4.255.0" do |s|
        s.platform = "x86_64-darwin-20"
      end
    end

    checksums = checksums_section_when_existing do |c|
      c.checksum gem_repo4, "libv8", "8.4.255.0", "x86_64-darwin-19"
      c.checksum gem_repo4, "libv8", "8.4.255.0", "x86_64-darwin-20"
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "libv8"
    G

    lockfile <<-G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          libv8 (8.4.255.0-x86_64-darwin-19)
          libv8 (8.4.255.0-x86_64-darwin-20)

      PLATFORMS
        x86_64-darwin

      DEPENDENCIES
        libv8
      #{checksums}
      BUNDLED WITH
         #{Bundler::VERSION}
    G

    previous_lockfile = lockfile

    %w[x86_64-darwin-19 x86_64-darwin-20].each do |platform|
      simulate_platform(Gem::Platform.new(platform)) do
        bundle "lock"
        expect(lockfile).to eq(previous_lockfile)

        bundle "install"
        expect(the_bundle).to include_gem("libv8 8.4.255.0 #{platform}")
      end
    end
  end

  it "does not conflict on ruby requirements when adding new platforms" do
    build_repo4 do
      build_gem "raygun-apm", "1.0.78" do |s|
        s.platform = "x86_64-linux"
        s.required_ruby_version = "< #{next_ruby_minor}.dev"
      end

      build_gem "raygun-apm", "1.0.78" do |s|
        s.platform = "universal-darwin"
        s.required_ruby_version = "< #{next_ruby_minor}.dev"
      end

      build_gem "raygun-apm", "1.0.78" do |s|
        s.platform = "x64-mingw32"
        s.required_ruby_version = "< #{next_ruby_minor}.dev"
      end

      build_gem "raygun-apm", "1.0.78" do |s|
        s.platform = "x64-mingw-ucrt"
        s.required_ruby_version = "< #{next_ruby_minor}.dev"
      end
    end

    gemfile <<-G
      source "https://localgemserver.test"

      gem "raygun-apm"
    G

    lockfile <<-L
      GEM
        remote: https://localgemserver.test/
        specs:
          raygun-apm (1.0.78-universal-darwin)

      PLATFORMS
        x86_64-darwin-19

      DEPENDENCIES
        raygun-apm

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock --add-platform x86_64-linux", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
  end

  it "does not crash on conflicting ruby requirements between platform versions in two different gems" do
    build_repo4 do
      build_gem "unf_ext", "0.0.8.2"

      build_gem "unf_ext", "0.0.8.2" do |s|
        s.required_ruby_version = [">= 2.4", "< #{previous_ruby_minor}"]
        s.platform = "x64-mingw32"
      end

      build_gem "unf_ext", "0.0.8.2" do |s|
        s.required_ruby_version = [">= #{previous_ruby_minor}", "< #{current_ruby_minor}"]
        s.platform = "x64-mingw-ucrt"
      end

      build_gem "google-protobuf", "3.21.12"

      build_gem "google-protobuf", "3.21.12" do |s|
        s.required_ruby_version = [">= 2.5", "< #{previous_ruby_minor}"]
        s.platform = "x64-mingw32"
      end

      build_gem "google-protobuf", "3.21.12" do |s|
        s.required_ruby_version = [">= #{previous_ruby_minor}", "< #{current_ruby_minor}"]
        s.platform = "x64-mingw-ucrt"
      end
    end

    gemfile <<~G
      source "https://gem.repo4"

      gem "google-protobuf"
      gem "unf_ext"
    G

    lockfile <<~L
      GEM
        remote: https://gem.repo4/
        specs:
          google-protobuf (3.21.12)
          unf_ext (0.0.8.2)

      PLATFORMS
        x64-mingw-ucrt
        x64-mingw32

      DEPENDENCIES
        google-protobuf
        unf_ext

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install --verbose", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s, "DEBUG_RESOLVER" => "1" }
  end

  it "respects lower bound ruby requirements" do
    build_repo4 do
      build_gem "our_private_gem", "0.1.0" do |s|
        s.required_ruby_version = ">= #{Gem.ruby_version}"
      end
    end

    gemfile <<-G
      source "https://localgemserver.test"

      gem "our_private_gem"
    G

    lockfile <<-L
      GEM
        remote: https://localgemserver.test/
        specs:
          our_private_gem (0.1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        our_private_gem

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "install", artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
  end

  context "when an update is available" do
    let(:repo) do
      build_repo2 do
        build_gem "foo", "2.0"
      end
      gem_repo2
    end

    before do
      lockfile(@lockfile)
    end

    it "does not implicitly update" do
      bundle "lock"

      checksums = checksums_section_when_existing do |c|
        c.checksum repo, "actionmailer", "2.3.2"
        c.checksum repo, "actionpack", "2.3.2"
        c.checksum repo, "activerecord", "2.3.2"
        c.checksum repo, "activeresource", "2.3.2"
        c.checksum repo, "activesupport", "2.3.2"
        c.checksum repo, "foo", "1.0"
        c.checksum repo, "rails", "2.3.2"
        c.checksum repo, "rake", rake_version
        c.checksum repo, "weakling", "0.0.3"
      end

      expected_lockfile = <<~L
        GEM
          remote: #{file_uri_for(repo)}/
          specs:
            actionmailer (2.3.2)
              activesupport (= 2.3.2)
            actionpack (2.3.2)
              activesupport (= 2.3.2)
            activerecord (2.3.2)
              activesupport (= 2.3.2)
            activeresource (2.3.2)
              activesupport (= 2.3.2)
            activesupport (2.3.2)
            foo (1.0)
            rails (2.3.2)
              actionmailer (= 2.3.2)
              actionpack (= 2.3.2)
              activerecord (= 2.3.2)
              activeresource (= 2.3.2)
              rake (= #{rake_version})
            rake (#{rake_version})
            weakling (0.0.3)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo
          rails
          weakling
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L

      expect(read_lockfile).to eq(expected_lockfile)
    end

    it "accounts for changes in the gemfile" do
      gemfile gemfile.gsub('"foo"', '"foo", "2.0"')
      bundle "lock"

      checksums = checksums_section_when_existing do |c|
        c.checksum repo, "actionmailer", "2.3.2"
        c.checksum repo, "actionpack", "2.3.2"
        c.checksum repo, "activerecord", "2.3.2"
        c.checksum repo, "activeresource", "2.3.2"
        c.checksum repo, "activesupport", "2.3.2"
        c.no_checksum "foo", "2.0"
        c.checksum repo, "rails", "2.3.2"
        c.checksum repo, "rake", rake_version
        c.checksum repo, "weakling", "0.0.3"
      end

      expected_lockfile = <<~L
        GEM
          remote: #{file_uri_for(repo)}/
          specs:
            actionmailer (2.3.2)
              activesupport (= 2.3.2)
            actionpack (2.3.2)
              activesupport (= 2.3.2)
            activerecord (2.3.2)
              activesupport (= 2.3.2)
            activeresource (2.3.2)
              activesupport (= 2.3.2)
            activesupport (2.3.2)
            foo (2.0)
            rails (2.3.2)
              actionmailer (= 2.3.2)
              actionpack (= 2.3.2)
              activerecord (= 2.3.2)
              activeresource (= 2.3.2)
              rake (= #{rake_version})
            rake (#{rake_version})
            weakling (0.0.3)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo (= 2.0)
          rails
          weakling
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L

      expect(read_lockfile).to eq(expected_lockfile)
    end
  end

  context "when a system gem has incorrect dependencies, different from the lockfile" do
    before do
      build_repo4 do
        build_gem "debug", "1.6.3" do |s|
          s.add_dependency "irb", ">= 1.3.6"
        end

        build_gem "irb", "1.5.0"
      end

      system_gems "irb-1.5.0", gem_repo: gem_repo4
      system_gems "debug-1.6.3", gem_repo: gem_repo4

      # simulate gemspec with wrong empty dependencies
      debug_gemspec_path = system_gem_path("specifications/debug-1.6.3.gemspec")
      debug_gemspec = Gem::Specification.load(debug_gemspec_path.to_s)
      debug_gemspec.dependencies.clear
      File.write(debug_gemspec_path, debug_gemspec.to_ruby)
    end

    it "respects the existing lockfile, even when reresolving" do
      gemfile <<~G
        source "#{file_uri_for(gem_repo4)}"

        gem "debug"
      G

      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            debug (1.6.3)
              irb (>= 1.3.6)
            irb (1.5.0)

        PLATFORMS
          x86_64-linux

        DEPENDENCIES
          debug
        #{checksums_section}
        BUNDLED WITH
           #{Bundler::VERSION}
      L

      simulate_platform "arm64-darwin-22" do
        bundle "lock"
      end

      checksums = checksums_section do |c|
        c.no_checksum "debug", "1.6.3"
        c.no_checksum "irb", "1.5.0"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            debug (1.6.3)
              irb (>= 1.3.6)
            irb (1.5.0)

        PLATFORMS
          arm64-darwin-22
          x86_64-linux

        DEPENDENCIES
          debug
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  it "properly shows resolution errors including OR requirements" do
    build_repo4 do
      build_gem "activeadmin", "2.13.1" do |s|
        s.add_dependency "railties", ">= 6.1", "< 7.1"
      end
      build_gem "actionpack", "6.1.4"
      build_gem "actionpack", "7.0.3.1"
      build_gem "actionpack", "7.0.4"
      build_gem "railties", "6.1.4" do |s|
        s.add_dependency "actionpack", "6.1.4"
      end
      build_gem "rails", "7.0.3.1" do |s|
        s.add_dependency "railties", "7.0.3.1"
      end
      build_gem "rails", "7.0.4" do |s|
        s.add_dependency "railties", "7.0.4"
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "rails", ">= 7.0.3.1"
      gem "activeadmin", "2.13.1"
    G

    bundle "lock", raise_on_error: false

    expect(err).to eq <<~ERR.strip
      Could not find compatible versions

      Because rails >= 7.0.4 depends on railties = 7.0.4
        and rails < 7.0.4 depends on railties = 7.0.3.1,
        railties = 7.0.3.1 OR = 7.0.4 is required.
      So, because railties = 7.0.3.1 OR = 7.0.4 could not be found in rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally,
        version solving has failed.
    ERR
  end

  it "is able to display some explanation on crazy irresolvable cases" do
    build_repo4 do
      build_gem "activeadmin", "2.13.1" do |s|
        s.add_dependency "ransack", "= 3.1.0"
      end

      # Activemodel is missing as a dependency in lockfile
      build_gem "ransack", "3.1.0" do |s|
        s.add_dependency "activemodel", ">= 6.0.4"
        s.add_dependency "activesupport", ">= 6.0.4"
      end

      %w[6.0.4 7.0.2.3 7.0.3.1 7.0.4].each do |version|
        build_gem "activesupport", version

        # Activemodel is only available on 6.0.4
        if version == "6.0.4"
          build_gem "activemodel", version do |s|
            s.add_dependency "activesupport", version
          end
        end

        build_gem "rails", version do |s|
          # Depednencies of Rails 7.0.2.3 are in reverse order
          if version == "7.0.2.3"
            s.add_dependency "activesupport", version
            s.add_dependency "activemodel", version
          else
            s.add_dependency "activemodel", version
            s.add_dependency "activesupport", version
          end
        end
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"

      gem "rails", ">= 7.0.2.3"
      gem "activeadmin", "= 2.13.1"
    G

    lockfile <<~L
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          activeadmin (2.13.1)
            ransack (= 3.1.0)
          ransack (3.1.0)
            activemodel (>= 6.0.4)

      PLATFORMS
        #{local_platform}

      DEPENDENCIES
        activeadmin (= 2.13.1)
        ransack (= 3.1.0)

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    bundle "lock", raise_on_error: false

    expect(err).to eq <<~ERR.strip
      Could not find compatible versions

          Because every version of activemodel depends on activesupport = 6.0.4
            and rails >= 7.0.2.3, < 7.0.3.1 depends on activesupport = 7.0.2.3,
            every version of activemodel is incompatible with rails >= 7.0.2.3, < 7.0.3.1.
          And because rails >= 7.0.2.3, < 7.0.3.1 depends on activemodel = 7.0.2.3,
            rails >= 7.0.2.3, < 7.0.3.1 cannot be used.
      (1) So, because rails >= 7.0.3.1, < 7.0.4 depends on activemodel = 7.0.3.1
            and rails >= 7.0.4 depends on activemodel = 7.0.4,
            rails >= 7.0.2.3 requires activemodel = 7.0.3.1 OR = 7.0.4.

          Because rails >= 7.0.2.3, < 7.0.3.1 depends on activemodel = 7.0.2.3
            and rails >= 7.0.3.1, < 7.0.4 depends on activesupport = 7.0.3.1,
            rails >= 7.0.2.3, < 7.0.4 requires activemodel = 7.0.2.3 or activesupport = 7.0.3.1.
          And because rails >= 7.0.4 depends on activesupport = 7.0.4
            and every version of activemodel depends on activesupport = 6.0.4,
            activemodel != 7.0.2.3 is incompatible with rails >= 7.0.2.3.
          And because rails >= 7.0.2.3 requires activemodel = 7.0.3.1 OR = 7.0.4 (1),
            rails >= 7.0.2.3 cannot be used.
          So, because Gemfile depends on rails >= 7.0.2.3,
            version solving has failed.
    ERR

    lockfile lockfile.gsub(/PLATFORMS\n  #{local_platform}/m, "PLATFORMS\n  #{lockfile_platforms("ruby")}")

    bundle "lock", raise_on_error: false

    expect(err).to eq <<~ERR.strip
      Could not find compatible versions

      Because rails >= 7.0.3.1, < 7.0.4 depends on activemodel = 7.0.3.1
        and rails >= 7.0.2.3, < 7.0.3.1 depends on activemodel = 7.0.2.3,
        rails >= 7.0.2.3, < 7.0.4 requires activemodel = 7.0.2.3 OR = 7.0.3.1.
      And because every version of activemodel depends on activesupport = 6.0.4,
        rails >= 7.0.2.3, < 7.0.4 requires activesupport = 6.0.4.
      Because rails >= 7.0.3.1, < 7.0.4 depends on activesupport = 7.0.3.1
        and rails >= 7.0.2.3, < 7.0.3.1 depends on activesupport = 7.0.2.3,
        rails >= 7.0.2.3, < 7.0.4 requires activesupport = 7.0.2.3 OR = 7.0.3.1.
      Thus, rails >= 7.0.2.3, < 7.0.4 cannot be used.
      And because rails >= 7.0.4 depends on activemodel = 7.0.4,
        rails >= 7.0.2.3 requires activemodel = 7.0.4.
      So, because activemodel = 7.0.4 could not be found in rubygems repository #{file_uri_for(gem_repo4)}/ or installed locally
        and Gemfile depends on rails >= 7.0.2.3,
        version solving has failed.
    ERR
  end

  it "does not accidentally resolves to prereleases" do
    build_repo4 do
      build_gem "autoproj", "2.0.3" do |s|
        s.add_dependency "autobuild", ">= 1.10.0.a"
        s.add_dependency "tty-prompt"
      end

      build_gem "tty-prompt", "0.6.0"
      build_gem "tty-prompt", "0.7.0"

      build_gem "autobuild", "1.10.0.b3"
      build_gem "autobuild", "1.10.1" do |s|
        s.add_dependency "tty-prompt", "~> 0.6.0"
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"
      gem "autoproj", ">= 2.0.0"
    G

    bundle "lock"
    expect(lockfile).to_not include("autobuild (1.10.0.b3)")
    expect(lockfile).to include("autobuild (1.10.1)")
  end

  # Newer rails depends on Bundler, while ancient Rails does not. Bundler tries
  # a first resolution pass that does not consider pre-releases. However, when
  # using a pre-release Bundler (like the .dev version), that results in that
  # pre-release being ignored and resolving to a version that does not depend on
  # Bundler at all. We should avoid that and still consider .dev Bundler.
  #
  it "does not ignore prereleases with there's only one candidate" do
    build_repo4 do
      build_gem "rails", "7.4.0.2" do |s|
        s.add_dependency "bundler", ">= 1.15.0"
      end

      build_gem "rails", "2.3.18"
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"
      gem "rails"
    G

    bundle "lock"
    expect(lockfile).to_not include("rails (2.3.18)")
    expect(lockfile).to include("rails (7.4.0.2)")
  end

  it "deals with platform specific incompatibilities" do
    build_repo4 do
      build_gem "activerecord", "6.0.6"
      build_gem "activerecord-jdbc-adapter", "60.4" do |s|
        s.platform = "java"
        s.add_dependency "activerecord", "~> 6.0.0"
      end
      build_gem "activerecord-jdbc-adapter", "61.0" do |s|
        s.platform = "java"
        s.add_dependency "activerecord", "~> 6.1.0"
      end
    end

    gemfile <<~G
      source "#{file_uri_for(gem_repo4)}"
      gem "activerecord", "6.0.6"
      gem "activerecord-jdbc-adapter", "61.0"
    G

    simulate_platform "universal-java-19" do
      bundle "lock", raise_on_error: false
    end

    expect(err).to include("Could not find compatible versions")
    expect(err).not_to include("ERROR REPORT TEMPLATE")
  end

  context "when re-resolving to include prereleases" do
    before do
      build_repo4 do
        build_gem "tzinfo-data", "1.2022.7"
        build_gem "rails", "7.1.0.alpha" do |s|
          s.add_dependency "activesupport"
        end
        build_gem "activesupport", "7.1.0.alpha"
      end
    end

    it "does not end up including gems scoped to other platforms in the lockfile" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem "rails"
        gem "tzinfo-data", platform: :windows
      G

      simulate_platform "x86_64-darwin-22" do
        bundle "lock"
      end

      expect(lockfile).not_to include("tzinfo-data (1.2022.7)")
    end
  end

  context "when resolving platform specific gems as indirect dependencies on truffleruby", :truffleruby_only do
    before do
      build_lib "foo", path: bundled_app do |s|
        s.add_dependency "nokogiri"
      end

      build_repo4 do
        build_gem "nokogiri", "1.14.2"
        build_gem "nokogiri", "1.14.2" do |s|
          s.platform = "x86_64-linux"
        end
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gemspec
      G
    end

    it "locks ruby specs" do
      checksums = checksums_section_when_existing do |c|
        c.no_checksum "foo", "1.0"
        c.no_checksum "nokogiri", "1.14.2"
      end

      simulate_platform "x86_64-linux" do
        bundle "lock"
      end

      expect(lockfile).to eq <<~L
        PATH
          remote: .
          specs:
            foo (1.0)
              nokogiri

        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            nokogiri (1.14.2)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end

  context "when adding a new gem that requires unlocking other transitive deps" do
    before do
      build_repo4 do
        build_gem "govuk_app_config", "0.1.0"

        build_gem "govuk_app_config", "4.13.0" do |s|
          s.add_dependency "railties", ">= 5.0"
        end

        %w[7.0.4.1 7.0.4.3].each do |v|
          build_gem "railties", v do |s|
            s.add_dependency "actionpack", v
            s.add_dependency "activesupport", v
          end

          build_gem "activesupport", v
          build_gem "actionpack", v
        end
      end

      gemfile <<~G
        source "#{file_uri_for(gem_repo4)}"

        gem "govuk_app_config"
        gem "activesupport", "7.0.4.3"
      G

      # Simulate out of sync lockfile because top level dependency on
      # activesuport has just been added to the Gemfile, and locked to a higher
      # version
      lockfile <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            actionpack (7.0.4.1)
            activesupport (7.0.4.1)
            govuk_app_config (4.13.0)
              railties (>= 5.0)
            railties (7.0.4.1)
              actionpack (= 7.0.4.1)
              activesupport (= 7.0.4.1)

        PLATFORMS
          arm64-darwin-22

        DEPENDENCIES
          govuk_app_config

        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end

    it "does not downgrade top level dependencies" do
      checksums = checksums_section_when_existing do |c|
        c.no_checksum "actionpack", "7.0.4.3"
        c.no_checksum "activesupport", "7.0.4.3"
        c.no_checksum "govuk_app_config", "4.13.0"
        c.no_checksum "railties", "7.0.4.3"
      end

      simulate_platform "arm64-darwin-22" do
        bundle "lock"
      end

      expect(lockfile).to eq <<~L
        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            actionpack (7.0.4.3)
            activesupport (7.0.4.3)
            govuk_app_config (4.13.0)
              railties (>= 5.0)
            railties (7.0.4.3)
              actionpack (= 7.0.4.3)
              activesupport (= 7.0.4.3)

        PLATFORMS
          arm64-darwin-22

        DEPENDENCIES
          activesupport (= 7.0.4.3)
          govuk_app_config
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      L
    end
  end
end
