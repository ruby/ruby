# frozen_string_literal: true

RSpec.describe "bundle install with content-addressable gems", :compact_index, rubygems: ">= 4.1.0.dev" do
  before do
    skip "Gem::ContentAddress not available" if ruby_core?
  end

  let(:current_abi) { "#{Gem.ruby_version.segments[0]}.#{Gem.ruby_version.segments[1]}" }
  let(:mismatched_abi) { "#{Gem.ruby_version.segments[0] + 1}.0" }

  it "installs the content-addressed gem when the Ruby ABI matches" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      expected_content_address_line = +"  mygem (1.0-x86_64-linux) #{content_address}"
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_linux'"
      end

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_matching_abi'"
      end

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed_mismatched_abi_1'"
      end

      second_mismatched_abi = "#{Gem.ruby_version.segments[0] + 2}.0"
      build_gem "mygem", "1.0", ruby_abi: second_mismatched_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

  it "does not swap a locked content-addressed gem for another artifact in frozen mode" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{current_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 content_addressed'"
      end

      build_gem "mygem", "1.0", ruby_abi: mismatched_abi, path: gem_repo2("gems") do |s|
        s.platform = Gem::Platform.new("x86_64-linux")
        s.required_ruby_version = "~> #{mismatched_abi}.0"
        s.write "lib/mygem.rb", "MYGEM = '1.0 mismatched'"
      end

      mismatched_file = Dir[gem_repo2("gems", "mygem-1.0-*.gem").to_s].find do |file|
        Gem::Package.new(file).spec.required_ruby_version.to_s == "~> #{mismatched_abi}.0"
      end
      mismatched_address = File.basename(mismatched_file, ".gem").rpartition("-").last
      mismatched_checksum = Digest::SHA256.file(mismatched_file).hexdigest

      gemfile <<~G
        source "https://gem.repo2"

        gem "mygem"
      G

      fat_checksum = Digest::SHA256.file(gem_repo2("gems", "mygem-1.0-x86_64-linux.gem")).hexdigest

      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            mygem (1.0-x86_64-linux)

        PLATFORMS
          x86_64-linux

        DEPENDENCIES
          mygem

        CONTENT ADDRESSES
          mygem (1.0-x86_64-linux) #{mismatched_address} sha256=#{mismatched_checksum}

        CHECKSUMS
          mygem (1.0-x86_64-linux) sha256=#{fat_checksum}

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle_config "frozen true"
      bundle "install", artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, raise_on_error: false

      expect(last_command).to be_failure
      expect(the_bundle).not_to include_gems "mygem 1.0 content_addressed"
      expect(lockfile).to include("mygem (1.0-x86_64-linux) #{mismatched_address}")
    end
  end

  it "omits the CHECKSUMS entry when only a content addressable build exists" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "othergem", "1.0"
      end

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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

      expected_content_address_line = +"  mygem (1.0-x86_64-linux) #{content_address}"
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

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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
end

RSpec.describe "bundle install with content-addressable gems invisible to pre-4.1 RubyGems clients", :compact_index, rubygems: ">= 4.1.0.a" do
  before do
    skip "Gem::ContentAddress not available" if ruby_core?
  end

  let(:current_abi) { "#{Gem.ruby_version.segments[0]}.#{Gem.ruby_version.segments[1]}" }

  it "installs content-addressed gems constrained so older clients refuse them" do
    simulate_platform "x86_64-linux" do
      build_repo2 do
        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      build_gem "mygem", "1.0", ruby_abi: current_abi, path: gem_repo2("gems") do |s|
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
