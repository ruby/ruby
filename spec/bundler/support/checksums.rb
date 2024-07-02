# frozen_string_literal: true

module Spec
  module Checksums
    class ChecksumsBuilder
      def initialize(enabled = true, &block)
        @enabled = enabled
        @checksums = {}
        yield self if block_given?
      end

      def initialize_copy(original)
        super
        @checksums = @checksums.dup
      end

      def checksum(repo, name, version, platform = Gem::Platform::RUBY)
        name_tuple = Gem::NameTuple.new(name, version, platform)
        gem_file = File.join(repo, "gems", "#{name_tuple.full_name}.gem")
        File.open(gem_file, "rb") do |f|
          register(name_tuple, Bundler::Checksum.from_gem(f, "#{gem_file} (via ChecksumsBuilder#checksum)"))
        end
      end

      def no_checksum(name, version, platform = Gem::Platform::RUBY)
        name_tuple = Gem::NameTuple.new(name, version, platform)
        register(name_tuple, nil)
      end

      def delete(name, platform = nil)
        @checksums.reject! {|k, _| k.name == name && (platform.nil? || k.platform == platform) }
      end

      def to_s
        return "" unless @enabled

        locked_checksums = @checksums.map do |name_tuple, checksum|
          checksum &&= " #{checksum.to_lock}"
          "  #{name_tuple.lock_name}#{checksum}\n"
        end

        "\nCHECKSUMS\n#{locked_checksums.sort.join}"
      end

      private

      def register(name_tuple, checksum)
        delete(name_tuple.name, name_tuple.platform)
        @checksums[name_tuple] = checksum
      end
    end

    def checksums_section(enabled = true, &block)
      ChecksumsBuilder.new(enabled, &block)
    end

    def checksums_section_when_existing(&block)
      begin
        enabled = lockfile.match?(/^CHECKSUMS$/)
      rescue Errno::ENOENT
        enabled = false
      end
      checksums_section(enabled, &block)
    end

    def checksum_to_lock(*args)
      checksums_section do |c|
        c.checksum(*args)
      end.to_s.sub(/^CHECKSUMS\n/, "").strip
    end

    def checksum_digest(*args)
      checksum_to_lock(*args).split(Bundler::Checksum::ALGO_SEPARATOR, 2).last
    end

    # if prefixes is given, removes all checksums where the line
    # has any of the prefixes on the line before the checksum
    # otherwise, removes all checksums from the lockfile
    def remove_checksums_from_lockfile(lockfile, *prefixes)
      head, remaining = lockfile.split(/^CHECKSUMS$/, 2)
      return lockfile unless remaining
      checksums, tail = remaining.split("\n\n", 2)

      prefixes =
        if prefixes.empty?
          nil
        else
          /(#{prefixes.map {|p| Regexp.escape(p) }.join("|")})/
        end

      checksums = checksums.each_line.map do |line|
        if prefixes.nil? || line.match?(prefixes)
          line.gsub(/ sha256=[a-f0-9]{64}/i, "")
        else
          line
        end
      end

      head.concat(
        "CHECKSUMS",
        checksums.join,
        "\n\n",
        tail
      )
    end

    def remove_checksums_section_from_lockfile(lockfile)
      head, remaining = lockfile.split(/^CHECKSUMS$/, 2)
      return lockfile unless remaining
      _checksums, tail = remaining.split("\n\n", 2)
      head.concat(tail)
    end

    def checksum_from_package(gem_file, name, version)
      name_tuple = Gem::NameTuple.new(name, version)

      checksum = nil

      File.open(gem_file, "rb") do |f|
        checksum = Bundler::Checksum.from_gem(f, gemfile)
      end

      "#{name_tuple.lock_name} #{checksum.to_lock}"
    end
  end
end
