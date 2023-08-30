# frozen_string_literal: true

module Bundler
  class Checksum
    DEFAULT_BLOCK_SIZE = 16_384
    private_constant :DEFAULT_BLOCK_SIZE

    class << self
      def from_gem_source(source, digest_algorithms: %w[sha256])
        raise ArgumentError, "not a valid gem source: #{source}" unless source.respond_to?(:with_read_io)

        source.with_read_io do |io|
          checksums = from_io(io, "#{source.path || source.inspect} gem source hexdigest", :digest_algorithms => digest_algorithms)
          io.rewind
          return checksums
        end
      end

      def from_io(io, source, digest_algorithms: %w[sha256])
        digests = digest_algorithms.to_h do |algo|
          [algo.to_s, Bundler::SharedHelpers.digest(algo.upcase).new]
        end

        until io.eof?
          ret = io.read DEFAULT_BLOCK_SIZE
          digests.each_value {|digest| digest << ret }
        end

        digests.map do |algo, digest|
          Checksum.new(algo, digest.hexdigest!, source)
        end
      end
    end

    attr_reader :algo, :digest, :sources
    def initialize(algo, digest, source)
      @algo = algo
      @digest = digest
      @sources = [source]
    end

    def ==(other)
      match?(other) && other.sources == sources
    end

    alias_method :eql?, :==

    def match?(other)
      other.is_a?(self.class) && other.digest == digest && other.algo == algo
    end

    def hash
      digest.hash
    end

    def to_s
      "#{to_lock} (from #{sources.first}#{", ..." if sources.size > 1})"
    end

    def to_lock
      "#{algo}-#{digest}"
    end

    def merge!(other)
      raise ArgumentError, "cannot merge checksums of different algorithms" unless algo == other.algo

      unless digest == other.digest
        raise SecurityError, <<~MESSAGE
          #{other}
          #{to_lock} from:
          * #{sources.join("\n* ")}
        MESSAGE
      end

      @sources.concat(other.sources).uniq!
      self
    end

    class Store
      attr_reader :store
      protected :store

      def initialize
        @store = {}
      end

      def initialize_copy(other)
        @store = {}
        other.store.each do |full_name, checksums|
          store[full_name] = checksums.dup
        end
      end

      def checksums(full_name)
        store[full_name]
      end

      def register_gem_package(spec, source)
        new_checksums = Checksum.from_gem_source(source)
        new_checksums.each do |checksum|
          register spec.full_name, checksum
        end
      rescue SecurityError
        expected = checksums(spec.full_name)
        gem_lock_name = GemHelpers.lock_name(spec.name, spec.version, spec.platform)
        raise SecurityError, <<~MESSAGE
          Bundler cannot continue installing #{gem_lock_name}.
          The checksum for the downloaded `#{spec.full_name}.gem` does not match \
          the known checksum for the gem.
          This means the contents of the downloaded \
          gem is different from what was uploaded to the server \
          or first used by your teammates, and could be a potential security issue.

          To resolve this issue:
          1. delete the downloaded gem located at: `#{source.path}`
          2. run `bundle install`

          If you are sure that the new checksum is correct, you can \
          remove the `#{gem_lock_name}` entry under the lockfile `CHECKSUMS` \
          section and rerun `bundle install`.

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config set --local disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`

          #{expected.map do |checksum|
            next unless actual = new_checksums.find {|c| c.algo == checksum.algo }
            next if actual.digest == checksum.digest

            "(More info: The expected #{checksum.algo.upcase} checksum was #{checksum.digest.inspect}, but the " \
            "checksum for the downloaded gem was #{actual.digest.inspect}. The expected checksum came from: #{checksum.sources.join(", ")})"
          end.compact.join("\n")}
        MESSAGE
      end

      def register(full_name, checksum)
        return unless checksum

        sums = (store[full_name] ||= [])
        sums.find {|c| c.algo == checksum.algo }&.merge!(checksum) || sums << checksum
      rescue SecurityError => e
        raise e.exception(<<~MESSAGE)
          Bundler found multiple different checksums for #{full_name}.
          This means that there are multiple different `#{full_name}.gem` files.
          This is a potential security issue, since Bundler could be attempting \
          to install a different gem than what you expect.

          #{e.message}
          To resolve this issue:
          1. delete any downloaded gems referenced above
          2. run `bundle install`

          If you are sure that the new checksum is correct, you can \
          remove the `#{full_name}` entry under the lockfile `CHECKSUMS` \
          section and rerun `bundle install`.

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config set --local disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`
        MESSAGE
      end

      def replace(full_name, checksum)
        store[full_name] = checksum ? [checksum] : nil
      end

      def register_store(other)
        other.store.each do |full_name, checksums|
          checksums.each {|checksum| register(full_name, checksum) }
        end
      end
    end
  end
end
