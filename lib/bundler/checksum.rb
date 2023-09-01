# frozen_string_literal: true

module Bundler
  class Checksum
    DEFAULT_ALGORITHM = "sha256"
    private_constant :DEFAULT_ALGORITHM
    DEFAULT_BLOCK_SIZE = 16_384
    private_constant :DEFAULT_BLOCK_SIZE

    class << self
      def from_gem(io, pathname, algo = DEFAULT_ALGORITHM)
        digest = Bundler::SharedHelpers.digest(algo.upcase).new
        buf = String.new(:capacity => DEFAULT_BLOCK_SIZE)
        digest << io.readpartial(DEFAULT_BLOCK_SIZE, buf) until io.eof?
        Checksum.new(algo, digest.hexdigest!, Source.new(:gem, pathname))
      end

      def from_api(digest, source_uri)
        # transform the bytes from base64 to hex, switch to unpack1 when we drop older rubies
        hexdigest = digest.length == 44 ? digest.unpack("m0").first.unpack("H*").first : digest

        if hexdigest.length != 64
          raise ArgumentError, "#{digest.inspect} is not a valid SHA256 hexdigest nor base64digest"
        end

        Checksum.new(DEFAULT_ALGORITHM, hexdigest, Source.new(:api, source_uri))
      end

      def from_lock(lock_checksum, lockfile_location)
        algo, digest = lock_checksum.strip.split("-", 2)
        Checksum.new(algo, digest, Source.new(:lock, lockfile_location))
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
      return nil unless match?(other)
      @sources.concat(other.sources).uniq!
      self
    end

    def formatted_sources
      sources.join("\n    and ").concat("\n")
    end

    def removable?
      sources.all?(&:removable?)
    end

    def removal_instructions
      msg = +""
      i = 1
      sources.each do |source|
        msg << "  #{i}. #{source.removal}\n"
        i += 1
      end
      msg << "  #{i}. run `bundle install`\n"
    end

    def inspect
      abbr = "#{algo}-#{digest[0, 8]}"
      from = "from #{sources.join(" and ")}"
      "#<#{self.class}:#{object_id} #{abbr} #{from}>"
    end

    class Source
      attr_reader :type, :location

      def initialize(type, location)
        @type = type
        @location = location
      end

      def removable?
        type == :lock || type == :gem
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.location == location
      end

      # phrased so that the usual string format is grammatically correct
      #   rake (10.3.2) sha256-abc123 from #{to_s}
      def to_s
        case type
        when :lock
          "the lockfile CHECKSUMS at #{location}"
        when :gem
          "the gem at #{location}"
        when :api
          "the API at #{location}"
        else
          "#{location} (#{type})"
        end
      end

      # A full sentence describing how to remove the checksum
      def removal
        case type
        when :lock
          "remove the matching checksum in #{location}"
        when :gem
          "remove the gem at #{location}"
        when :api
          "checksums from #{location} cannot be locally modified, you may need to update your sources"
        else
          "remove #{location} (#{type})"
        end
      end
    end

    class Store
      attr_reader :store
      protected :store

      def initialize
        @store = {}
      end

      def initialize_copy(other)
        @store = {}
        other.store.each do |name_tuple, checksums|
          store[name_tuple] = checksums.dup
        end
      end

      def inspect
        "#<#{self.class}:#{object_id} size=#{store.size}>"
      end

      def fetch(spec, algo = DEFAULT_ALGORITHM)
        store[spec.name_tuple]&.fetch(algo, nil)
      end

      # Replace when the new checksum is from the same source.
      # The primary purpose of this registering checksums from gems where there are
      # duplicates of the same gem (according to full_name) in the index.
      # In particular, this is when 2 gems have two similar platforms, e.g.
      # "darwin20" and "darwin-20", both of which resolve to darwin-20.
      # In the Index, the later gem replaces the former, so we do that here.
      #
      # However, if the new checksum is from a different source, we register like normal.
      # This ensures a mismatch error where there are multiple top level sources
      # that contain the same gem with different checksums.
      def replace(spec, checksum)
        return if Bundler.settings[:disable_checksum_validation]
        return unless checksum

        name_tuple = spec.name_tuple
        checksums = (store[name_tuple] ||= {})
        existing = checksums[checksum.algo]

        # we assume only one source because this is used while building the index
        if !existing || existing.sources.first == checksum.sources.first
          checksums[checksum.algo] = checksum
        else
          register_checksum(name_tuple, checksum)
        end
      end

      def register(spec, checksum)
        return if Bundler.settings[:disable_checksum_validation]
        return unless checksum
        register_checksum(spec.name_tuple, checksum)
      end

      def merge!(other)
        other.store.each do |name_tuple, checksums|
          checksums.each do |_algo, checksum|
            register_checksum(name_tuple, checksum)
          end
        end
      end

      def to_lock(spec)
        name_tuple = spec.name_tuple
        if checksums = store[name_tuple]
          "#{name_tuple.lock_name} #{checksums.values.map(&:to_lock).sort.join(",")}"
        else
          name_tuple.lock_name
        end
      end

      private

      def register_checksum(name_tuple, checksum)
        return unless checksum
        checksums = (store[name_tuple] ||= {})
        existing = checksums[checksum.algo]

        if !existing
          checksums[checksum.algo] = checksum
        elsif existing.merge!(checksum)
          checksum
        else
          raise ChecksumMismatchError.new(name_tuple, existing, checksum)
        end
      end
    end
  end
end
