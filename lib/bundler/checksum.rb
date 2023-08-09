# frozen_string_literal: true

module Bundler
  class Checksum
    class Store
      attr_reader :store
      protected :store

      def initialize
        @store = {}
      end

      def initialize_copy(o)
        @store = {}
        o.store.each do |k, v|
          @store[k] = v.dup
        end
      end

      def [](spec)
        sums = @store[spec.full_name]

        Checksum.new(spec.name, spec.version, spec.platform, sums&.transform_values(&:digest))
      end

      def register(spec, checksums)
        register_full_name(spec.full_name, checksums)
      end

      def register_triple(name, version, platform, checksums)
        register_full_name(GemHelpers.spec_full_name(name, version, platform), checksums)
      end

      def delete_full_name(full_name)
        @store.delete(full_name)
      end

      def register_full_name(full_name, checksums)
        sums = (@store[full_name] ||= {})

        checksums.each do |checksum|
          algo = checksum.algo
          if multi = sums[algo]
            multi.merge(checksum)
          else
            sums[algo] = Multi.new [checksum]
          end
        end
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

      def use(other)
        other.store.each do |k, v|
          register_full_name k, v.values
        end
      end
    end

    class Single
      attr_reader :algo, :digest, :source
      def initialize(algo, digest, source)
        @algo = algo
        @digest = digest
        @source = source
      end

      def ==(other)
        other.is_a?(Single) && other.digest == digest && other.algo == algo && source == other.source
      end

      def hash
        digest.hash
      end

      alias_method :eql?, :==

      def to_s
        "#{algo}-#{digest} (from #{source})"
      end
    end

    class Multi
      attr_reader :algo, :digest, :checksums
      protected :checksums

      def initialize(checksums)
        @checksums = checksums

        unless checksums && checksums.size > 0
          raise ArgumentError, "must provide at least one checksum"
        end

        first = checksums.first
        @algo = first.algo
        @digest = first.digest
      end

      def initialize_copy(o)
        @checksums = o.checksums.dup
        @algo = o.algo
        @digest = o.digest
      end

      def merge(other)
        raise ArgumentError, "cannot merge checksums of different algorithms" unless algo == other.algo
        unless digest == other.digest
          raise SecurityError, <<~MESSAGE
            #{other}
            #{self} from:
            * #{sources.join("\n* ")}
          MESSAGE
        end

        case other
        when Single
          @checksums << other
        when Multi
          @checksums.concat(other.checksums)
        else
          raise ArgumentError
        end
        @checksums.uniq!

        self
      end

      def sources
        @checksums.map(&:source)
      end

      def to_s
        "#{algo}-#{digest}"
      end
    end

    attr_reader :name, :version, :platform, :checksums

    SHA256 = %r{\Asha256-([a-z0-9]{64}|[A-Za-z0-9+\/=]{44})\z}.freeze
    private_constant :SHA256

    def initialize(name, version, platform, checksums = {})
      @name     = name
      @version  = version
      @platform = platform || Gem::Platform::RUBY
      @checksums = checksums || {}

      # can expand this validation when we support more hashing algos later
      if !@checksums.is_a?(::Hash) || (@checksums.any? && !@checksums.key?("sha256"))
        raise ArgumentError, "invalid checksums (#{@checksums.inspect})"
      end
      if @checksums.any? {|_, checksum| !checksum.is_a?(String) }
        raise ArgumentError, "invalid checksums (#{@checksums})"
      end
    end

    def self.digests_from_file_source(file_source, digest_algorithms: %w[sha256])
      raise ArgumentError, "not a valid file source: #{file_source}" unless file_source.respond_to?(:with_read_io)

      digests = digest_algorithms.map do |digest_algorithm|
        [digest_algorithm.to_s, Bundler::SharedHelpers.digest(digest_algorithm.upcase).new]
      end.to_h

      file_source.with_read_io do |io|
        until io.eof?
          block = io.read(16_384)
          digests.each_value {|digest| digest << block }
        end

        io.rewind
      end

      digests
    end

    def full_name
      GemHelpers.spec_full_name(@name, @version, @platform)
    end

    def match_spec?(spec)
      name == spec.name &&
        version == spec.version &&
        platform.to_s == spec.platform.to_s
    end

    def to_lock
      out = String.new
      out << "  #{GemHelpers.lock_name(name, version, platform)}"
      checksums.sort_by(&:first).each_with_index do |(algo, checksum), idx|
        out << (idx.zero? ? " " : ",")
        out << algo << "-" << checksum
      end
      out << "\n"

      out
    end

    def match?(other)
      return false unless match_spec?(other)
      match_digests?(other.checksums)
    end

    def match_digests?(digests)
      return true if checksums.empty? && digests.empty?

      common_algos = checksums.keys & digests.keys
      return true if common_algos.empty?

      common_algos.all? do |algo|
        checksums[algo] == digests[algo]
      end
    end

    def merge!(other)
      raise ArgumentError, "can't merge checksums for different specs" unless match_spec?(other)

      merge_digests!(other.checksums)
    end

    def merge_digests!(digests)
      if digests.any? {|_, checksum| !checksum.is_a?(String) }
        raise ArgumentError, "invalid checksums (#{digests})"
      end
      @checksums = @checksums.merge(digests) do |algo, ours, theirs|
        if ours != theirs
          raise ArgumentError, "Digest mismatch for #{algo}:\n\t* #{ours.inspect}\n\t* #{theirs.inspect}"
        end
        ours
      end

      self
    end

    private

    def sha256
      @checksums.find {|c| c =~ SHA256 }
    end
  end
end
