# frozen_string_literal: true

RSpec.describe "bundle install with content-addressable gems", :compact_index, rubygems: ">= 4.1.0.a" do
  before { skip_unless_content_addressing_available! }

  it "installs the content-addressed gem when the Ruby ABI matches" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"

      cached_files = Dir.glob(default_bundle_path("cache", "mygem-1.0-*.gem").to_s)
      expect(cached_files.size).to eq(1), "expected exactly one cached gem file, found: #{cached_files}"
      expect(cached_files.first).to match(/mygem-1\.0-[0-9a-f]{8,64}\.gem$/)
      expect(default_bundle_path("cache", "mygem-1.0-x86_64-linux.gem")).not_to exist

      expect(lockfile).to match(/^    mygem \(1\.0-x86_64-linux\)$/)

      content_address = File.basename(cached_files.first, ".gem").rpartition("-").last
      digest = Digest::SHA256.file(cached_files.first).hexdigest
      expect(content_address).to eq(digest[0, content_address.length])

      checksums_enabled = lockfile.match?(/^CHECKSUMS$/)

      expected_content_address_line = +"  mygem (1.0-x86_64-linux) #{content_address} abi=#{current_abi}"
      expected_content_address_line << " sha256=#{digest}" if checksums_enabled
      expect(lockfile).to include("CONTENT ADDRESSES\n#{expected_content_address_line}\n")

      checksums = checksums_section_when_enabled do |c|
        c.checksum(gem_repo2, "mygem", "1.0", "x86_64-linux")
      end
      expect(lockfile).to include(checksums.to_s)
      expect(lockfile).not_to include("(1.0-#{content_address})")
    end
  end

  it "resolves a content-addressed binary from the local cache after a lockfile round-trip" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      cached_file = Dir[default_bundle_path("cache", "mygem-1.0-*.gem").to_s].first
      FileUtils.mkdir_p(bundled_app("vendor/cache"))
      FileUtils.cp(cached_file, bundled_app("vendor/cache"))

      gem_dir = Dir[default_bundle_path("gems", "mygem-1.0-*").to_s].first
      pristine_system_gems
      bundle "install --local"

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
      expect(Dir[default_bundle_path("gems", "mygem-1.0-*").to_s].first).to eq(gem_dir)
    end
  end

  it "falls back to the non-content-addressed gem when the content-addressed gem requires a different Ruby ABI" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 not_content_addressed"
    end
  end

  it "does not treat a content-addressed suffix as content-addressable when platform metadata is missing" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = "abcdef12"
          s.write "lib/mygem.rb", "MYGEM = '1.0 hex_platform'"
        end
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, raise_on_error: false
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(err).to include("Could not find gem 'mygem'")
    end
  end

  it "falls back to the non-content-addressed gem when the content-addressed gem is for a different platform" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("arm64-darwin")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 not_content_addressed"
    end
  end

  it "installs the content-addressed gem matching the current platform when multiple platforms are available" do
    simulate_platform "x86_64-linux" do
      build_repo2

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_linux'"
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("arm64-darwin")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_darwin'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed_linux"
    end
  end

  it "installs the content-addressed gem even when a more specific non-content-addressed platform gem exists" do
    simulate_platform "arm64-darwin-23" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("arm64-darwin-23")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("arm64-darwin")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
    end
  end

  it "falls back to the pure-ruby gem when the content-addressed gem requires a different Ruby ABI" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.write "lib/mygem.rb", "MYGEM = '1.0 pure_ruby'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 pure_ruby"
    end
  end

  it "installs the ABI-compatible content-addressed gem when multiple content-addressed gems are available for the same platform" do
    simulate_platform "x86_64-linux" do
      build_repo2

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_matching_abi'"
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_mismatched_abi'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed_matching_abi"
    end
  end

  it "installs the higher non-content-addressed version over a lower content-addressed version" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "2.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '2.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 2.0 not_content_addressed"
    end
  end

  it "falls back to the non-content-addressed gem when all content-addressed gems require a different Ruby ABI" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_mismatched_abi_1'"
      end

      second_mismatched_abi = "#{Gem.ruby_version.segments[0] + 2}.0"
      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{second_mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_mismatched_abi_2'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 not_content_addressed"
    end
  end

  it "reports the Ruby version requirement when only incompatible content-addressed gems exist" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "other", "1.0"
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, raise_on_error: false
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(last_command).to be_failure
      expect(err).to include("every version of mygem depends on Ruby ~> #{mismatched_abi}.0")
      expect(err).not_to include("Could not find gem 'mygem'")
    end
  end

  it "installs a locked content-addressed gem in frozen mode" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"

      pristine_system_gems
      bundle_config "frozen true"
      bundle "install", artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
    end
  end

  it "omits the CHECKSUMS entry when only a content addressable build exists" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "othergem", "1.0"
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"

      cached_file = Dir[default_bundle_path("cache", "mygem-1.0-*.gem").to_s].first
      content_address = File.basename(cached_file, ".gem").rpartition("-").last
      digest = Digest::SHA256.file(cached_file).hexdigest

      expected_content_address_line = +"  mygem (1.0-x86_64-linux) #{content_address} abi=#{current_abi}"
      expected_content_address_line << " sha256=#{digest}" if lockfile.match?(/^CHECKSUMS$/)
      expect(lockfile).to include("CONTENT ADDRESSES\n#{expected_content_address_line}\n")

      expect(lockfile).not_to match(/^  mygem \(1\.0-x86_64-linux\)$/)

      original_lockfile = lockfile
      bundle_config "frozen true"
      bundle "install", artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      expect(lockfile).to eq(original_lockfile)
    end
  end

  it "fails when the downloaded content-addressed gem hash does not match the filename" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.required_ruby_version = "~> #{current_abi}.0"
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      ca_gem = Dir[gem_repo2("gems", "mygem-1.0-[0-9a-f]*.gem")].first
      non_ca_gem = gem_repo2("gems", "mygem-1.0-x86_64-linux.gem")
      FileUtils.cp non_ca_gem, ca_gem

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, raise_on_error: false
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(err).to include("content address mismatch")
    end
  end

  context "when several content-addressed gems exist for the locked platform" do
    before do
      build_repo2_with_content_addressed_gems

      gemfile <<~G
        source "https://gem.repo2"

        gem "mygem"
      G
    end

    it "records the resolving Ruby's ABI and locks only its content-addressed gems" do
      simulate_platform "x86_64-linux" do
        bundle_with_content_addressed_gems "install"

        expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
        expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n")
        expect(locked_addresses).to eq(addresses(current_abi))

        original_lockfile = lockfile
        pristine_system_gems
        bundle_config "frozen true"
        bundle_with_content_addressed_gems "install"

        expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
        expect(lockfile).to eq(original_lockfile)
      end
    end

    it "installs the content-addressed gem for the running Ruby among those a platform row lists, keeping the lockfile" do
      simulate_platform "x86_64-linux" do
        lockfile_with_content_addresses(addresses(current_abi, mismatched_abi), ruby_abis: [current_abi, mismatched_abi].sort)
        original_lockfile = lockfile

        bundle_with_content_addressed_gems "install"
        expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
        expect(lockfile).to eq(original_lockfile)

        pristine_system_gems
        bundle_config "frozen true"
        bundle_with_content_addressed_gems "install"
        expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
        expect(lockfile).to eq(original_lockfile)
      end
    end

    it "falls back to the platform gem in frozen mode under a Ruby ABI the lockfile does not cover, like a locked ruby platform, until that Ruby ABI is locked" do
      simulate_platform "x86_64-linux" do
        lockfile_with_content_addresses(addresses(mismatched_abi), ruby_abis: [mismatched_abi])
        original_lockfile = lockfile

        bundle_config "frozen true"
        bundle_with_content_addressed_gems "install"

        expect(the_bundle).to include_gems "mygem 1.0 not_content_addressed"
        expect(lockfile).to eq(original_lockfile)

        bundle_with_content_addressed_gems "lock --add-ruby-abi #{current_abi}"
        bundle_with_content_addressed_gems "install"
        expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
      end
    end

    it "drops an untagged locked content address the source no longer offers on an online resolution, but keeps it offline" do
      simulate_platform "x86_64-linux" do
        lockfile_with_content_addresses({ "0000000000000000" => nil }.merge(addresses(current_abi)), ruby_abis: [current_abi])
        bundle_with_content_addressed_gems "install"

        bundle_with_content_addressed_gems "lock --add-ruby-abi #{mismatched_abi} --local", raise_on_error: false
        expect(locked_addresses).to include("0000000000000000" => nil)

        bundle_with_content_addressed_gems "lock --add-ruby-abi #{mismatched_abi}"
        expect(locked_addresses).to eq(addresses(current_abi, mismatched_abi))
      end
    end

    context "when the lockfile predates the RUBY ABIS section" do
      ["4.0.0", "4.1.0.beta1"].each do |bundled_with|
        it "locks the content-addressed gem when `bundle update --bundler` upgrades a lockfile without content addresses from Bundler #{bundled_with}" do
          simulate_platform "x86_64-linux" do
            update_repo2 { build_gem "bundler", Bundler::VERSION }
            lockfile_with_content_addresses(bundled_with: bundled_with)

            bundle_with_content_addressed_gems "update --bundler"

            expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
            expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n")
            expect(locked_addresses).to eq(addresses(current_abi))
          end
        end
      end

      it "installs the content-addressed gem a beta locked for the running Ruby in frozen mode, keeping the lockfile" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses({ current_address => nil })
          original_lockfile = lockfile

          bundle_config "frozen true"
          bundle_with_content_addressed_gems "install"

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile).to eq(original_lockfile)
        end
      end

      it "installs the multi-ABI gem in frozen mode when a beta locked only another Ruby's content-addressed gem" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses({ mismatched_address => nil }, checksums: true)
          original_lockfile = lockfile

          bundle_config "frozen true"
          bundle_with_content_addressed_gems "install"

          expect(the_bundle).to include_gems "mygem 1.0 not_content_addressed"
          expect(lockfile).to eq(original_lockfile)
        end
      end

      it "re-resolves once to record the running Ruby's ABI and its content-addressed gem, then finds no changes" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses({ mismatched_address => nil })

          bundle_with_content_addressed_gems "install"

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile.scan(/^    mygem \(1\.0-x86_64-linux\)$/).size).to eq(1)
          expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n")
          expect(locked_addresses).to eq(addresses(current_abi))

          original_lockfile = lockfile
          bundle_with_content_addressed_gems "install --verbose"

          expect(out).to include("Found no changes, using resolution from the lockfile")
          expect(lockfile).to eq(original_lockfile)
        end
      end

      it "records the running Ruby's ABI instead of falling back to the ruby gem" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses({ mismatched_address => nil }, ruby_gem: true)

          bundle_with_content_addressed_gems "install"

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n")
          expect(locked_addresses).to eq(addresses(current_abi))
        end
      end
    end

    context "when resolving locally" do
      it "fails under an uncovered Ruby ABI without touching the lockfile, until an online install locks its gems" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses(addresses(mismatched_abi), ruby_abis: [mismatched_abi])
          original_lockfile = lockfile

          bundle_with_content_addressed_gems "install --local", raise_on_error: false

          expect(last_command).to be_failure
          expect(err).to include("Could not find mygem-1.0-x86_64-linux in locally installed gems")
          expect(lockfile).to eq(original_lockfile)

          bundle_with_content_addressed_gems "install"

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n  #{mismatched_abi}\n")
          expect(locked_addresses).to eq(addresses(current_abi, mismatched_abi))
        end
      end

      it "records the running Ruby's ABI and its already installed content-addressed gem" do
        simulate_platform "x86_64-linux" do
          lockfile_with_content_addresses(addresses(current_abi), ruby_abis: [current_abi])
          bundle_with_content_addressed_gems "install"

          lockfile_with_content_addresses(addresses(mismatched_abi), ruby_abis: [mismatched_abi])
          bundle_with_content_addressed_gems "install --local"

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n  #{mismatched_abi}\n")
          expect(locked_addresses).to eq(addresses(current_abi, mismatched_abi))

          original_lockfile = lockfile
          bundle_with_content_addressed_gems "install --local --verbose"

          expect(out).to include("Found no changes, using resolution from the lockfile")
          expect(lockfile).to eq(original_lockfile)
        end
      end
    end

    context "when the Gemfile has a ruby directive" do
      def install_with_ruby_directive(directive)
        lockfile_with_content_addresses(addresses(current_abi, mismatched_abi), ruby_abis: [current_abi, mismatched_abi].sort, ruby_version: Bundler::RubyVersion.system.to_s)

        gemfile <<~G
          source "https://gem.repo2"

          #{directive}
          gem "mygem"
        G

        bundle_with_content_addressed_gems "install"
      end

      {
        "an exact version" => -> { %(ruby "#{RUBY_VERSION}") },
        "a pessimistic patch constraint" => -> { %(ruby "~> #{current_abi}.0") },
        "a range ending before the next Ruby" => -> { %(ruby ">= #{current_abi}.0", "< #{mismatched_abi}") },
      }.each do |kind, directive|
        it "drops the content addresses for the Ruby ABIs #{kind} rules out" do
          simulate_platform "x86_64-linux" do
            install_with_ruby_directive instance_exec(&directive)

            expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
            expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n")
            expect(locked_addresses).to eq(addresses(current_abi))
          end
        end
      end

      it "keeps the content addresses for every Ruby ABI the directive allows" do
        simulate_platform "x86_64-linux" do
          install_with_ruby_directive %(ruby ">= #{current_abi}.0", "< #{mismatched_abi}.1")

          expect(the_bundle).to include_gems "mygem 1.0 content_addressed"
          expect(lockfile).to include("RUBY ABIS\n  #{current_abi}\n  #{mismatched_abi}\n")
          expect(locked_addresses).to eq(addresses(current_abi, mismatched_abi))
        end
      end

      it "checks the directive against the locked Ruby ABIs at boot without loading the resolver" do
        simulate_platform "x86_64-linux" do
          install_with_ruby_directive %(ruby "#{RUBY_VERSION}")

          ruby "require 'bundler/setup'; puts defined?(Gem::PubGrub).inspect"
          expect(out).to eq("nil")
        end
      end
    end
  end

  it "falls back to the locked ruby gem in frozen mode under a Ruby ABI the lockfile does not cover, without a platform warning" do
    simulate_platform "x86_64-linux" do
      build_repo2_with_content_addressed_gems(platform_gem: false)

      gemfile <<~G
        source "https://gem.repo2"

        gem "mygem"
      G

      lockfile_with_content_addresses(addresses(mismatched_abi), ruby_gem: true, ruby_abis: [mismatched_abi])
      original_lockfile = lockfile

      bundle_config "frozen true"
      bundle_with_content_addressed_gems "install"

      expect(err).not_to include("platform specific gems are getting installed")
      expect(the_bundle).to include_gems "mygem 1.0"
      expect(lockfile).to eq(original_lockfile)
    end
  end
end

RSpec.describe "bundle install with content-addressable gems invisible to pre-4.1 RubyGems clients", :compact_index, rubygems: ">= 4.1.0.a" do
  before do
    skip "A prerelease Ruby does not satisfy the ~> X.Y.0 ABI pin of content-addressed gems" if Gem.ruby_version.prerelease?
  end

  it "installs content-addressed gems constrained so older clients refuse them" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      install_gemfile <<~G, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
        source "https://gem.repo2"

        gem "mygem"
      G

      expect(the_bundle).to include_gems "mygem 1.0 content_addressed"

      expect(Dir[default_bundle_path("specifications", "mygem-1.0-*.gemspec").to_s]).to be_empty

      installed_gemspec = Dir[default_bundle_path("specifications", current_abi, "mygem-1.0-*.gemspec").to_s].first
      expect(installed_gemspec).not_to be_nil
      spec = Gem::Specification.load(installed_gemspec)

      expect(spec.required_rubygems_version).to eq(Gem::Requirement.new(">= 4.1.0.a"))
      expect(spec.required_rubygems_version.satisfied_by?(Gem::Version.new("4.0.9"))).to be false
      expect(spec.required_rubygems_version.satisfied_by?(Gem.rubygems_version)).to be true
    end
  end
end
