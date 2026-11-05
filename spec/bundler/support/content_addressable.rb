# frozen_string_literal: true

module Spec
  module ContentAddressable
    def skip_unless_content_addressing_available!
      skip "Gem::ContentAddress not available" if ruby_core?
      skip "A prerelease Ruby does not satisfy the ~> X.Y.0 ABI pin of content-addressed gems" if Gem.ruby_version.prerelease?
    end

    def bundle_with_content_addressed_gems(command, **options)
      bundle command, artifice: "compact_index_v2", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, **options
    end

    def current_abi
      Gem.ruby_version.segments.first(2).join(".")
    end

    def mismatched_abi
      "#{Gem.ruby_version.segments[0] + 1}.0"
    end

    def build_repo2_with_content_addressed_gems(platform_gem: true)
      build_repo2 do
        build_gem "mygem", "1.0"
        next unless platform_gem

        build_gem "mygem", "1.0" do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.write "lib/mygem.rb", "MYGEM = '1.0 not_content_addressed'"
        end
      end

      { current_abi => "content_addressed", mismatched_abi => "mismatched" }.each do |ruby_abi, label|
        build_gem "mygem", "1.0", content_addressable: true, path: gem_repo2("gems") do |s|
          s.platform = Gem::Platform.new("x86_64-linux")
          s.required_ruby_version = "~> #{ruby_abi}.0"
          s.write "lib/mygem.rb", "MYGEM = '1.0 #{label}'"
        end
      end
    end

    def addresses_by_abi
      @addresses_by_abi ||= Dir[gem_repo2("gems", "mygem-1.0-*.gem").to_s].to_h do |path|
        ruby_abi = Gem::ContentAddress.ruby_abi_for(Gem::Package.new(path).spec.required_ruby_version)
        [ruby_abi, File.basename(path, ".gem").rpartition("-").last]
      end
    end

    def current_address
      addresses_by_abi.fetch(current_abi)
    end

    def mismatched_address
      addresses_by_abi.fetch(mismatched_abi)
    end

    def addresses(*ruby_abis)
      ruby_abis.to_h {|ruby_abi| [addresses_by_abi.fetch(ruby_abi), ruby_abi] }
    end

    def locked_addresses(name: "mygem", version: "1.0", platform: "x86_64-linux")
      lockfile.scan(/^  #{Regexp.escape("#{name} (#{version}-#{platform})")} ([0-9a-f]+)(?: abi=(\d+\.\d+))?(?: sha\d+=\S+)?$/).to_h
    end

    def lockfile_with_content_addresses(content_addresses = {}, name: "mygem", version: "1.0", platform: "x86_64-linux", ruby_gem: false, checksums: false, ruby_abis: nil, ruby_version: nil, bundled_with: Bundler::VERSION)
      lock_name = "#{name} (#{version}-#{platform})"
      rows = content_addresses.map do |address, ruby_abi|
        row = "#{lock_name} #{address}"
        row += " abi=#{ruby_abi}" if ruby_abi
        row += " sha256=#{checksum_digest(gem_repo2, name, version, address)}" if checksums
        row
      end.sort

      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            #{"#{name} (#{version})\n    " if ruby_gem}#{lock_name}

        PLATFORMS
          #{platform}

        DEPENDENCIES
          #{name}
        #{"\nCONTENT ADDRESSES\n#{rows.map {|row| "  #{row}\n" }.join}" if rows.any?}
        #{"\nCHECKSUMS\n  #{lock_name} sha256=#{checksum_digest(gem_repo2, name, version, platform)}\n" if checksums}
        #{"\nRUBY ABIS\n#{ruby_abis.map {|ruby_abi| "  #{ruby_abi}\n" }.join}" if ruby_abis}
        #{"\nRUBY VERSION\n   #{ruby_version}\n" if ruby_version}
        BUNDLED WITH
           #{bundled_with}
      L
    end
  end
end
