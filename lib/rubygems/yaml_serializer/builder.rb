# frozen_string_literal: true

module Gem
  module YAMLSerializer
    class Builder
      VALID_OPS = %w[= != > < >= <= ~>].freeze
      ARRAY_FIELDS = %w[files test_files executables extra_rdoc_files].freeze
      MAX_ALIAS_EXPANSION = 100_000

      def initialize(permitted_classes: [], permitted_symbols: [], aliases: true)
        @permitted_classes = permitted_classes.map {|c| "!ruby/object:#{c}" }
        @permitted_symbols = permitted_symbols
        @aliases = aliases
        @anchor_values = {}
        @anchor_sizes = {}
        @expanded_size = 0
        @alias_expansion = 0
      end

      def build(node)
        return nil if node.nil?

        result = build_node(node)

        if result.is_a?(Hash) && result[:tag] == "!ruby/object:Gem::Specification"
          build_specification(result)
        else
          result
        end
      end

      private

      def build_node(node)
        start = @expanded_size
        case node
        when nil then nil
        when AliasRef then resolve_alias(node)
        when Scalar then store_anchor(node.anchor, node.value, start)
        when Mapping then store_anchor(node.anchor, build_mapping(node), start)
        when Sequence then store_anchor(node.anchor, node.items.map {|item| build_node(item) }, start)
        else node # already a Ruby object
        end
      end

      def resolve_alias(node)
        raise Psych::AliasesNotEnabled unless @aliases
        unless @anchor_values.key?(node.name)
          raise Psych::AnchorNotDefined, node.name if defined?(Psych::AnchorNotDefined)
          raise Psych::BadAlias, "An alias referenced an unknown anchor: #{node.name}"
        end
        # Charge the expanded size of the anchor, weighing scalars by length,
        # so neither nested aliases nor aliases to a long string blow up.
        size = @anchor_sizes.fetch(node.name)
        @expanded_size += size
        @alias_expansion += size
        if @alias_expansion > MAX_ALIAS_EXPANSION
          raise Psych::BadAlias, "exceeded maximum alias expansion (#{MAX_ALIAS_EXPANSION})"
        end
        @anchor_values.fetch(node.name)
      end

      def store_anchor(name, value, start)
        @expanded_size += value.is_a?(String) ? 1 + value.bytesize : 1
        if name
          @anchor_values[name] = value
          @anchor_sizes[name] = @expanded_size - start
        end
        value
      end

      def build_mapping(node)
        validate_tag!(node.tag) if node.tag

        result = case node.tag
                 when "!ruby/object:Gem::Version"
                   build_version(node)
                 when "!ruby/object:Gem::Platform"
                   build_platform(node)
                 when "!ruby/object:Gem::Requirement", "!ruby/object:Gem::Version::Requirement"
                   build_requirement(node)
                 when "!ruby/object:Gem::Dependency"
                   build_dependency(node)
                 when nil
                   build_hash(node)
                 when "!ruby/object:Gem::Specification"
                   hash = build_hash(node)
                   hash[:tag] = node.tag
                   hash
                 else
                   raise ArgumentError, "undefined class/module #{node.tag.sub("!ruby/object:", "")}"
        end

        result
      end

      def build_hash(node)
        result = {}
        each_pair(node) do |key, value_node|
          value = build_node(value_node)

          if ARRAY_FIELDS.include?(key)
            value = normalize_array_field(value)
          end

          result[key] = value
        end
        result
      end

      def build_version(node)
        hash = pairs_to_hash(node)
        Gem::Version.new((hash["version"] || hash["value"]).to_s)
      end

      PLATFORM_FIELDS = %w[cpu os version].freeze
      PLATFORM_ALLOWED_IVARS = %w[cpu os version value].freeze

      def build_platform(node)
        hash = pairs_to_hash(node)
        if (hash.keys & PLATFORM_FIELDS).any?
          Gem::Platform.new([hash["cpu"], hash["os"], hash["version"]])
        elsif hash["value"].is_a?(Array)
          # Malformed platform (e.g. sequence instead of mapping).
          # Return the raw value so yaml_initialize handles it like Psych does.
          hash["value"]
        else
          plat = Gem::Platform.allocate
          hash.each do |k, v|
            plat.instance_variable_set(:"@#{k}", v) if PLATFORM_ALLOWED_IVARS.include?(k)
          end
          plat
        end
      end

      def build_requirement(node)
        r = Gem::Requirement.allocate
        hash = pairs_to_hash(node)
        reqs = hash["requirements"] || hash["value"]

        if reqs.is_a?(Array) && !reqs.empty?
          safe_reqs = []
          reqs.each do |item|
            if item.is_a?(Array) && item.size == 2
              op = item[0].to_s
              ver = item[1]
              if VALID_OPS.include?(op)
                version_obj = ver.is_a?(Gem::Version) ? ver : Gem::Version.new(ver.to_s)
                safe_reqs << [op, version_obj]
              end
            elsif item.is_a?(String)
              parsed = Gem::Requirement.parse(item)
              safe_reqs << parsed
            end
          rescue Gem::Requirement::BadRequirementError, Gem::Version::BadVersionError
            # Skip malformed items silently
          end
          reqs = safe_reqs unless safe_reqs.empty?
        end

        r.instance_variable_set(:@requirements, reqs)
        r
      end

      def build_dependency(node)
        hash = pairs_to_hash(node)
        d = Gem::Dependency.allocate
        d.instance_variable_set(:@name, hash["name"])

        d.instance_variable_set(:@requirement, hash["requirement"] || hash["version_requirements"])

        raw_type = hash["type"]
        if raw_type
          name = raw_type.to_s.sub(/^:/, "")
          validate_symbol!(name)
          type = name.to_sym
        else
          type = :runtime
        end
        d.instance_variable_set(:@type, type)

        d.instance_variable_set(:@prerelease, ["true", true].include?(hash["prerelease"]))
        d.instance_variable_set(:@version_requirements, d.instance_variable_get(:@requirement))
        d
      end

      def build_specification(hash)
        spec = Gem::Specification.allocate

        normalize_specification_version!(hash)
        normalize_array_fields!(hash)

        spec.yaml_initialize("!ruby/object:Gem::Specification", hash)
        spec
      end

      def pairs_to_hash(node)
        result = {}
        each_pair(node) do |key, value_node|
          result[key] = build_node(value_node)
        end
        result
      end

      def each_pair(node)
        pairs = node.pairs
        i = 0
        while i < pairs.size
          yield pairs[i], pairs[i + 1]
          i += 2
        end
      end

      def validate_tag!(tag)
        return if @permitted_classes.include?(tag)
        raise_disallowed_class!(tag)
      end

      def raise_disallowed_class!(tag)
        if defined?(Psych::VERSION)
          raise Psych::DisallowedClass.new("load", tag)
        else
          raise Psych::DisallowedClass, "Tried to load unspecified class: #{tag}"
        end
      end

      def validate_symbol!(name)
        return if @permitted_symbols.empty? || @permitted_symbols.include?(name)

        label = ":#{name}"
        if defined?(Psych::VERSION)
          raise Psych::DisallowedClass.new("load", label)
        else
          raise Psych::DisallowedClass, "Tried to load unspecified class: #{label}"
        end
      end

      def normalize_specification_version!(hash)
        val = hash["specification_version"]
        return unless val && !val.is_a?(Integer)
        hash["specification_version"] = val.to_i if val.is_a?(String) && /\A\d+\z/.match?(val)
      end

      def normalize_array_fields!(hash)
        ARRAY_FIELDS.each do |field|
          hash[field] = normalize_array_field(hash[field]) if hash[field]
        end
      end

      def normalize_array_field(value)
        if value.is_a?(Hash)
          value.values.flatten.compact
        elsif !value.is_a?(Array) && value
          [value].flatten.compact
        else
          value
        end
      end
    end
  end
end
