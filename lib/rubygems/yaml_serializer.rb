# frozen_string_literal: true

module Gem
  module YAMLSerializer
    Scalar = Struct.new(:value, :tag, :anchor, keyword_init: true)

    Mapping = Struct.new(:pairs, :tag, :anchor, keyword_init: true) do
      def initialize(pairs: [], tag: nil, anchor: nil)
        super
      end
    end

    Sequence = Struct.new(:items, :tag, :anchor, keyword_init: true) do
      def initialize(items: [], tag: nil, anchor: nil)
        super
      end
    end

    AliasRef = Struct.new(:name, keyword_init: true)

    class Parser
      MAPPING_KEY_RE = /^((?:[^#:]|:[^ ])+):(?:[ ]+(.*))?$/

      def initialize(source)
        @lines = source.split(/\r?\n/)
        @anchors = {}
        strip_document_prefix
      end

      def parse
        return nil if @lines.empty?

        root = nil
        while @lines.any?
          before = @lines.size
          node = parse_node(-1)
          @lines.shift if @lines.size == before && @lines.any?

          if root.is_a?(Mapping) && node.is_a?(Mapping)
            root.pairs.concat(node.pairs)
          elsif root.nil?
            root = node
          end
        end
        root
      end

      private

      def strip_document_prefix
        return if @lines.empty?
        return unless @lines[0]&.start_with?("---")

        if @lines[0].strip == "---"
          @lines.shift
        else
          @lines[0] = @lines[0].sub(/^---\s*/, "")
        end
      end

      def parse_node(base_indent)
        skip_blank_and_comments
        return nil if @lines.empty?

        indent = @lines[0][/^ */].size
        return nil if indent < base_indent

        line = @lines[0]

        return parse_alias_ref if line.lstrip.start_with?("*")

        anchor = consume_anchor

        if line.lstrip.start_with?("- ") || line.lstrip == "-"
          parse_sequence(indent, anchor)
        elsif line.lstrip =~ MAPPING_KEY_RE && !line.lstrip.start_with?("!ruby/object:")
          parse_mapping(indent, anchor)
        elsif line.lstrip.start_with?("!ruby/object:")
          parse_tagged_node(indent, anchor)
        elsif line.lstrip.start_with?("|")
          modifier = line.lstrip[1..].to_s.strip
          @lines.shift
          register_anchor(anchor, Scalar.new(value: parse_block_scalar(indent, modifier)))
        else
          parse_plain_scalar(indent, anchor)
        end
      end

      def parse_sequence(indent, anchor)
        items = []
        while @lines.any? && @lines[0][/^ */].size == indent &&
              (@lines[0].lstrip.start_with?("- ") || @lines[0].lstrip == "-")
          content = @lines.shift.lstrip[1..].strip
          item_anchor, content = extract_item_anchor(content)
          item = parse_sequence_item(content, indent)
          items << register_anchor(item_anchor, item)
        end
        register_anchor(anchor, Sequence.new(items: items))
      end

      def parse_sequence_item(content, indent)
        if content.start_with?("*")
          parse_inline_alias(content)
        elsif content.empty?
          @lines.any? && @lines[0][/^ */].size > indent ? parse_node(indent) : nil
        elsif content.start_with?("!ruby/object:")
          parse_tagged_content(content.strip, indent)
        elsif content.start_with?("-")
          @lines.unshift("#{" " * (indent + 2)}#{content}")
          parse_node(indent)
        elsif content =~ MAPPING_KEY_RE && !content.start_with?("!ruby/object:")
          @lines.unshift("#{" " * (indent + 2)}#{content}")
          parse_node(indent)
        elsif content.start_with?("|")
          Scalar.new(value: parse_block_scalar(indent, content[1..].to_s.strip))
        else
          parse_inline_scalar(content, indent)
        end
      end

      def parse_mapping(indent, anchor)
        pairs = []
        while @lines.any? && @lines[0][/^ */].size == indent &&
              @lines[0].lstrip =~ MAPPING_KEY_RE && !@lines[0].lstrip.start_with?("!ruby/object:")
          l = @lines.shift
          l.lstrip =~ MAPPING_KEY_RE
          key = $1.strip
          val = strip_comment($2.to_s.strip)

          val_anchor, val = consume_value_anchor(val)
          value = parse_mapping_value(val, indent)
          value = register_anchor(val_anchor, value) if val_anchor

          pairs << [Scalar.new(value: key), value]
        end
        register_anchor(anchor, Mapping.new(pairs: pairs))
      end

      def parse_mapping_value(val, indent)
        if val.start_with?("*")
          parse_inline_alias(val)
        elsif val.start_with?("!ruby/object:")
          parse_tagged_content(val.strip, indent)
        elsif val.empty?
          if @lines.any? &&
             (@lines[0].lstrip.start_with?("- ") || @lines[0].lstrip == "-") &&
             @lines[0][/^ */].size == indent
            parse_node(indent)
          else
            parse_node(indent + 1)
          end
        elsif val == "[]"
          Sequence.new
        elsif val == "{}"
          Mapping.new
        elsif val.start_with?("|")
          Scalar.new(value: parse_block_scalar(indent, val[1..].to_s.strip))
        else
          parse_inline_scalar(val, indent)
        end
      end

      def parse_tagged_node(indent, anchor)
        tag = @lines.shift.lstrip.strip
        nested = parse_node(indent)
        apply_tag(nested, tag, anchor)
      end

      def parse_tagged_content(tag, indent)
        nested = parse_node(indent)
        apply_tag(nested, tag, nil)
      end

      def apply_tag(node, tag, anchor)
        if node.is_a?(Mapping)
          node.tag = tag
          node.anchor = anchor
          node
        else
          Mapping.new(pairs: [[Scalar.new(value: "value"), node]], tag: tag, anchor: anchor)
        end
      end

      def parse_block_scalar(base_indent, modifier)
        parts = []
        block_indent = nil

        while @lines.any?
          if @lines[0].strip.empty?
            parts << "\n"
            @lines.shift
          else
            line_indent = @lines[0][/^ */].size
            break if line_indent <= base_indent
            block_indent ||= line_indent
            parts << @lines.shift[block_indent..].to_s << "\n"
          end
        end

        res = parts.join
        res.chomp! if modifier == "-" && res.end_with?("\n")
        res
      end

      def parse_plain_scalar(indent, anchor)
        result = coerce(@lines.shift.strip)
        return register_anchor(anchor, result) if result.is_a?(Mapping) || result.is_a?(Sequence)

        while result.is_a?(String) && @lines.any? &&
              !@lines[0].strip.empty? && @lines[0][/^ */].size > indent
          result << " " << @lines.shift.strip
        end
        register_anchor(anchor, Scalar.new(value: result))
      end

      def parse_inline_scalar(val, indent)
        result = coerce(val)
        return result if result.is_a?(Mapping) || result.is_a?(Sequence)

        while result.is_a?(String) && @lines.any? &&
              !@lines[0].strip.empty? && @lines[0][/^ */].size > indent
          result << " " << @lines.shift.strip
        end
        Scalar.new(value: result)
      end

      def coerce(val)
        val = val.sub(/^! /, "") if val.start_with?("! ")

        if val =~ /^"(.*)"$/
          $1.gsub(/\\"/, '"').gsub(/\\n/, "\n").gsub(/\\r/, "\r").gsub(/\\t/, "\t").gsub(/\\\\/, "\\")
        elsif val =~ /^'(.*)'$/
          $1.gsub(/''/, "'")
        elsif val == "true"
          true
        elsif val == "false"
          false
        elsif val == "nil"
          nil
        elsif val == "{}"
          Mapping.new
        elsif val =~ /^\[(.*)\]$/
          inner = $1.strip
          return Sequence.new if inner.empty?
          items = inner.split(/\s*,\s*/).reject(&:empty?).map {|e| Scalar.new(value: coerce(e)) }
          Sequence.new(items: items)
        elsif /^\d{4}-\d{2}-\d{2}/.match?(val)
          require "time"
          begin
            Time.parse(val)
          rescue ArgumentError
            val
          end
        elsif /^-?\d+$/.match?(val)
          val.to_i
        else
          val
        end
      end

      def parse_alias_ref
        AliasRef.new(name: @lines.shift.lstrip[1..].strip)
      end

      def parse_inline_alias(content)
        AliasRef.new(name: content[1..].strip)
      end

      def consume_anchor
        line = @lines[0]
        return nil unless line.lstrip =~ /^&(\S+)\s+/

        anchor = $1
        @lines[0] = line.sub(/&#{Regexp.escape(anchor)}\s+/, "")
        anchor
      end

      def extract_item_anchor(content)
        return [nil, content] unless content =~ /^&(\S+)/

        anchor = $1
        [anchor, content.sub(/^&#{Regexp.escape(anchor)}\s*/, "")]
      end

      def consume_value_anchor(val)
        return [nil, val] unless val =~ /^&(\S+)\s+/

        anchor = $1
        [anchor, val.sub(/^&#{Regexp.escape(anchor)}\s+/, "")]
      end

      def register_anchor(name, node)
        if name
          @anchors[name] = node
          node.anchor = name if node.respond_to?(:anchor=)
        end
        node
      end

      def skip_blank_and_comments
        @lines.shift while @lines.any? &&
                           (@lines[0].strip.empty? || @lines[0].lstrip.start_with?("#"))
      end

      def strip_comment(val)
        return val unless val.include?("#")
        return val if val.lstrip.start_with?("#")

        in_single = false
        in_double = false
        escape = false

        val.each_char.with_index do |ch, i|
          if escape
            escape = false
            next
          end

          if in_single
            in_single = false if ch == "'"
          elsif in_double
            if ch == "\\"
              escape = true
            elsif ch == '"'
              in_double = false
            end
          else
            case ch
            when "'" then in_single = true
            when '"' then in_double = true
            when "#" then return val[0...i].rstrip
            end
          end
        end

        val
      end
    end

    class Builder
      VALID_OPS = %w[= != > < >= <= ~>].freeze
      ARRAY_FIELDS = %w[rdoc_options files test_files executables requirements extra_rdoc_files].freeze

      def initialize(permitted_classes: [], permitted_symbols: [], aliases: true)
        @permitted_tags = Array(permitted_classes).map do |c|
          "!ruby/object:#{c.is_a?(Module) ? c.name : c}"
        end
        @permitted_symbols = permitted_symbols
        @aliases = aliases
        @anchor_values = {}
      end

      def build(node)
        return {} if node.nil?

        result = build_node(node)

        if result.is_a?(Hash) &&
           (result[:tag] == "!ruby/object:Gem::Specification" ||
            result["tag"] == "!ruby/object:Gem::Specification")
          build_specification(result)
        else
          result
        end
      end

      private

      def build_node(node)
        case node
        when nil then nil
        when AliasRef then resolve_alias(node)
        when Scalar then store_anchor(node.anchor, node.value)
        when Mapping then build_mapping(node)
        when Sequence then store_anchor(node.anchor, node.items.map {|item| build_node(item) })
        else node # already a Ruby object
        end
      end

      def resolve_alias(node)
        raise ArgumentError, "YAML aliases are not allowed" unless @aliases
        @anchor_values.fetch(node.name, nil)
      end

      def store_anchor(name, value)
        @anchor_values[name] = value if name
        value
      end

      def build_mapping(node)
        validate_tag!(node.tag) if node.tag
        check_anchor!(node)

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
                 else
                   hash = build_hash(node)
                   hash[:tag] = node.tag
                   hash
        end

        store_anchor(node.anchor, result)
      end

      def build_hash(node)
        result = {}
        node.pairs.each do |key_node, value_node|
          key = key_node.is_a?(Scalar) ? key_node.value.to_s : build_node(key_node).to_s
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

      def build_platform(node)
        hash = pairs_to_hash(node)
        if hash["value"]
          Gem::Platform.new(hash["value"])
        else
          Gem::Platform.new([hash["cpu"], hash["os"], hash["version"]])
        end
      end

      def build_requirement(node)
        r = Gem::Requirement.allocate
        hash = pairs_to_hash(node)
        reqs = hash["requirements"] || hash["value"]
        reqs = [] unless reqs.is_a?(Array)

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

        requirement = build_safe_requirement(hash["requirement"])
        d.instance_variable_set(:@requirement, requirement)

        type = hash["type"]
        type = type ? type.to_s.sub(/^:/, "").to_sym : :runtime
        validate_symbol!(type)
        d.instance_variable_set(:@type, type)

        d.instance_variable_set(:@prerelease, ["true", true].include?(hash["prerelease"]))
        d.instance_variable_set(:@version_requirements, d.instance_variable_get(:@requirement))
        d
      end

      def build_specification(hash)
        spec = Gem::Specification.allocate

        normalize_specification_version!(hash)
        normalize_rdoc_options!(hash)
        normalize_array_fields!(hash)

        spec.yaml_initialize("!ruby/object:Gem::Specification", hash)
        spec
      end

      def pairs_to_hash(node)
        result = {}
        node.pairs.each do |key_node, value_node|
          key = key_node.is_a?(Scalar) ? key_node.value.to_s : build_node(key_node).to_s
          result[key] = build_node(value_node)
        end
        result
      end

      def build_safe_requirement(req_value)
        return Gem::Requirement.default unless req_value

        converted = req_value
        return Gem::Requirement.default unless converted.is_a?(Gem::Requirement)

        reqs = converted.instance_variable_get(:@requirements)
        if reqs&.is_a?(Array)
          valid = reqs.all? do |item|
            next true if item == Gem::Requirement::DefaultRequirement
            item.is_a?(Array) && item.size >= 2 && VALID_OPS.include?(item[0].to_s)
          end
          valid ? converted : Gem::Requirement.default
        else
          converted
        end
      rescue StandardError
        Gem::Requirement.default
      end

      def validate_tag!(tag)
        unless @permitted_tags.include?(tag)
          raise ArgumentError, "Disallowed class: #{tag}"
        end
      end

      def validate_symbol!(sym)
        if @permitted_symbols.any? && !@permitted_symbols.include?(sym.to_s)
          raise ArgumentError, "Disallowed symbol: #{sym.inspect}"
        end
      end

      def check_anchor!(node)
        if node.anchor
          raise ArgumentError, "YAML aliases are not allowed" unless @aliases
        end
      end

      def normalize_specification_version!(hash)
        val = hash["specification_version"]
        return unless val && !val.is_a?(Integer)
        hash["specification_version"] = val.to_i if val.is_a?(String) && /\A\d+\z/.match?(val)
      end

      def normalize_rdoc_options!(hash)
        opts = hash["rdoc_options"]
        if opts.is_a?(Hash)
          hash["rdoc_options"] = opts.values.flatten.compact.map(&:to_s)
        elsif opts.is_a?(Array)
          hash["rdoc_options"] = opts.flat_map do |opt|
            if opt.is_a?(Hash)
              opt.flat_map {|k, v| [k.to_s, v.to_s] }
            elsif opt.is_a?(String)
              opt
            else
              opt.to_s
            end
          end
        end
      end

      def normalize_array_fields!(hash)
        ARRAY_FIELDS.each do |field|
          next if field == "rdoc_options" # already handled
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

    class Emitter
      def emit(obj)
        "---#{emit_node(obj, 0)}"
      end

      private

      def emit_node(obj, indent, quote: false)
        case obj
        when Gem::Specification then emit_specification(obj, indent)
        when Gem::Version       then emit_version(obj, indent)
        when Gem::Platform      then emit_platform(obj, indent)
        when Gem::Requirement   then emit_requirement(obj, indent)
        when Gem::Dependency    then emit_dependency(obj, indent)
        when Hash               then emit_hash(obj, indent)
        when Array              then emit_array(obj, indent)
        when Time               then emit_time(obj)
        when String             then emit_string(obj, indent, quote: quote)
        when Numeric, Symbol, TrueClass, FalseClass, nil
          " #{obj.inspect}\n"
        else
          " #{obj.to_s.inspect}\n"
        end
      end

      def emit_specification(spec, indent)
        parts = [" !ruby/object:Gem::Specification\n"]
        parts << "#{pad(indent)}name:#{emit_node(spec.name, indent + 2)}"
        parts << "#{pad(indent)}version:#{emit_node(spec.version, indent + 2)}"
        parts << "#{pad(indent)}platform: #{spec.platform}\n"
        if spec.platform.to_s != spec.original_platform.to_s
          parts << "#{pad(indent)}original_platform: #{spec.original_platform}\n"
        end

        attributes = Gem::Specification.attribute_names.map(&:to_s).sort - %w[name version platform]
        attributes.each do |name|
          val = spec.instance_variable_get("@#{name}")
          next if val.nil?
          parts << "#{pad(indent)}#{name}:#{emit_node(val, indent + 2)}"
        end

        res = parts.join
        res << "\n" unless res.end_with?("\n")
        res
      end

      def emit_version(ver, indent)
        " !ruby/object:Gem::Version\n" \
          "#{pad(indent)}version: #{emit_node(ver.version.to_s, indent + 2).lstrip}"
      end

      def emit_platform(plat, indent)
        " !ruby/object:Gem::Platform\n" \
          "#{pad(indent)}cpu: #{plat.cpu.inspect}\n" \
          "#{pad(indent)}os: #{plat.os.inspect}\n" \
          "#{pad(indent)}version: #{plat.version.inspect}\n"
      end

      def emit_requirement(req, indent)
        " !ruby/object:Gem::Requirement\n" \
          "#{pad(indent)}requirements:#{emit_node(req.requirements, indent + 2)}"
      end

      def emit_dependency(dep, indent)
        [
          " !ruby/object:Gem::Dependency\n",
          "#{pad(indent)}name: #{emit_node(dep.name, indent + 2).lstrip}",
          "#{pad(indent)}requirement:#{emit_node(dep.requirement, indent + 2)}",
          "#{pad(indent)}type: #{emit_node(dep.type, indent + 2).lstrip}",
          "#{pad(indent)}prerelease: #{emit_node(dep.prerelease?, indent + 2).lstrip}",
          "#{pad(indent)}version_requirements:#{emit_node(dep.requirement, indent + 2)}",
        ].join
      end

      def emit_hash(hash, indent)
        if hash.empty?
          " {}\n"
        else
          parts = ["\n"]
          hash.each do |k, v|
            is_symbol = k.is_a?(Symbol) || (k.is_a?(String) && k.start_with?(":"))
            key_str = k.is_a?(Symbol) ? k.inspect : k.to_s
            parts << "#{pad(indent)}#{key_str}:#{emit_node(v, indent + 2, quote: is_symbol)}"
          end
          parts.join
        end
      end

      def emit_array(arr, indent)
        if arr.empty?
          " []\n"
        else
          parts = ["\n"]
          arr.each do |v|
            parts << "#{pad(indent)}-#{emit_node(v, indent + 2)}"
          end
          parts.join
        end
      end

      def emit_time(time)
        " #{time.utc.strftime("%Y-%m-%d %H:%M:%S.%N Z")}\n"
      end

      def emit_string(str, indent, quote: false)
        if str.include?("\n")
          emit_block_scalar(str, indent)
        elsif needs_quoting?(str, quote)
          " #{str.to_s.inspect}\n"
        else
          " #{str}\n"
        end
      end

      def emit_block_scalar(str, indent)
        parts = [str.end_with?("\n") ? " |\n" : " |-\n"]
        str.each_line do |line|
          parts << "#{pad(indent + 2)}#{line}"
        end
        res = parts.join
        res << "\n" unless res.end_with?("\n")
        res
      end

      def needs_quoting?(str, quote)
        quote || str.empty? ||
          str =~ /^[!*&:@%$]/ || str =~ /^-?\d+(\.\d+)?$/ || str =~ /^[<>=-]/ ||
          str == "true" || str == "false" || str == "nil" ||
          str.include?(":") || str.include?("#") || str.include?("[") || str.include?("]") ||
          str.include?("{") || str.include?("}") || str.include?(",")
      end

      def pad(indent)
        " " * indent
      end
    end

    module_function

    def dump(obj)
      Emitter.new.emit(obj)
    end

    def load(str, permitted_classes: [], permitted_symbols: [], aliases: true)
      return {} if str.nil? || str.empty?

      ast = Parser.new(str).parse
      return {} if ast.nil?

      Builder.new(
        permitted_classes: permitted_classes,
        permitted_symbols: permitted_symbols,
        aliases: aliases
      ).build(ast)
    end
  end
end
