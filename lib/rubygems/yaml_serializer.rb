# frozen_string_literal: true

module Gem
  module YAMLSerializer
    module_function

    def dump(obj)
      "---#{dump_obj(obj, 0)}"
    end

    def dump_obj(obj, indent, quote: false)
      case obj
      when Gem::Specification
        parts = [" !ruby/object:Gem::Specification\n"]
        parts << "#{" " * indent}name:#{dump_obj(obj.name, indent + 2)}"
        parts << "#{" " * indent}version:#{dump_obj(obj.version, indent + 2)}"
        parts << "#{" " * indent}platform: #{obj.platform}\n"
        if obj.platform.to_s != obj.original_platform.to_s
          parts << "#{" " * indent}original_platform: #{obj.original_platform}\n"
        end

        attributes = Gem::Specification.attribute_names.map(&:to_s).sort - %w[name version platform]
        attributes.each do |name|
          val = obj.instance_variable_get("@#{name}")
          next if val.nil?
          parts << "#{" " * indent}#{name}:#{dump_obj(val, indent + 2)}"
        end
        res = parts.join
        res << "\n" unless res.end_with?("\n")
        res
      when Gem::Version
        " !ruby/object:Gem::Version\n#{" " * indent}version: #{dump_obj(obj.version.to_s, indent + 2).lstrip}"
      when Gem::Platform
        " !ruby/object:Gem::Platform\n#{" " * indent}cpu: #{obj.cpu.inspect}\n#{" " * indent}os: #{obj.os.inspect}\n#{" " * indent}version: #{obj.version.inspect}\n"
      when Gem::Requirement
        " !ruby/object:Gem::Requirement\n#{" " * indent}requirements:#{dump_obj(obj.requirements, indent + 2)}"
      when Gem::Dependency
        [
          " !ruby/object:Gem::Dependency\n",
          "#{" " * indent}name: #{dump_obj(obj.name, indent + 2).lstrip}",
          "#{" " * indent}requirement:#{dump_obj(obj.requirement, indent + 2)}",
          "#{" " * indent}type: #{dump_obj(obj.type, indent + 2).lstrip}",
          "#{" " * indent}prerelease: #{dump_obj(obj.prerelease?, indent + 2).lstrip}",
          "#{" " * indent}version_requirements:#{dump_obj(obj.requirement, indent + 2)}",
        ].join
      when Hash
        if obj.empty?
          " {}\n"
        else
          parts = ["\n"]
          obj.each do |k, v|
            is_symbol = k.is_a?(Symbol) || (k.is_a?(String) && k.start_with?(":"))
            key_str = k.is_a?(Symbol) ? k.inspect : k.to_s
            parts << "#{" " * indent}#{key_str}:#{dump_obj(v, indent + 2, quote: is_symbol)}"
          end
          parts.join
        end
      when Array
        if obj.empty?
          " []\n"
        else
          parts = ["\n"]
          obj.each do |v|
            parts << "#{" " * indent}-#{dump_obj(v, indent + 2)}"
          end
          parts.join
        end
      when Time
        " #{obj.utc.strftime("%Y-%m-%d %H:%M:%S.%N Z")}\n"
      when String
        if obj.include?("\n")
          parts = [obj.end_with?("\n") ? " |\n" : " |-\n"]
          obj.each_line do |line|
            parts << "#{" " * (indent + 2)}#{line}"
          end
          res = parts.join
          res << "\n" unless res.end_with?("\n")
          res
        elsif quote || obj.empty? || obj =~ /^[!*&:@%$]/ || obj =~ /^-?\d+(\.\d+)?$/ || obj =~ /^[<>=-]/ ||
              obj == "true" || obj == "false" || obj == "nil" ||
              obj.include?(":") || obj.include?("#") || obj.include?("[") || obj.include?("]") ||
              obj.include?("{") || obj.include?("}") || obj.include?(",")
          " #{obj.to_s.inspect}\n"
        else
          " #{obj}\n"
        end
      when Numeric, Symbol, TrueClass, FalseClass, nil
        " #{obj.inspect}\n"
      else
        " #{obj.to_s.inspect}\n"
      end
    end

    def load(str, permitted_classes: [], permitted_symbols: [], aliases: true)
      return {} if str.nil? || str.empty?
      lines = str.split(/\r?\n/)
      if lines[0]&.start_with?("---")
        if lines[0].strip == "---"
          lines.shift
        else
          lines[0] = lines[0].sub(/^---\s*/, "")
        end
      end

      permitted_tags = build_permitted_tags(permitted_classes)
      anchors = {}
      data = nil
      while lines.any?
        before_count = lines.size
        parsed = parse_any(lines, -1, permitted_tags, aliases, anchors)
        if lines.size == before_count && lines.any?
          lines.shift
        end

        if data.is_a?(Hash) && parsed.is_a?(Hash)
          data.merge!(parsed)
        elsif data.nil?
          data = parsed
        end
      end

      return {} if data.nil?

      if data.is_a?(Hash) && (data[:tag] == "!ruby/object:Gem::Specification" || data["tag"] == "!ruby/object:Gem::Specification")
        convert_to_spec(data, permitted_symbols)
      else
        convert_any(data, permitted_symbols)
      end
    end

    def parse_any(lines, base_indent, permitted_tags, aliases, anchors)
      while lines.any? && (lines[0].strip.empty? || lines[0].lstrip.start_with?("#"))
        lines.shift
      end
      return nil if lines.empty?

      indent = lines[0][/^ */].size
      return nil if indent < base_indent

      line = lines[0]

      # Check for alias reference (*anchor)
      if line.lstrip.start_with?("*")
        unless aliases
          raise ArgumentError, "YAML aliases are not allowed"
        end
        alias_name = lines.shift.lstrip[1..-1].strip
        return anchors[alias_name]
      end

      # Extract anchor if present (&anchor)
      anchor_name = nil
      if line.lstrip =~ /^&(\S+)\s+/
        unless aliases
          raise ArgumentError, "YAML aliases are not allowed"
        end
        anchor_name = $1
        line = line.sub(/&#{Regexp.escape(anchor_name)}\s+/, "")
        lines[0] = line
      end

      if line.lstrip.start_with?("- ") || line.lstrip == "-"
        res = []
        while lines.any? && lines[0][/^ */].size == indent && (lines[0].lstrip.start_with?("- ") || lines[0].lstrip == "-")
          l = lines.shift
          content = l.lstrip[1..-1].strip

          # Check for anchor in array item
          item_anchor = nil
          if content =~ /^&(\S+)/
            unless aliases
              raise ArgumentError, "YAML aliases are not allowed"
            end
            item_anchor = $1
            content = content.sub(/^&#{Regexp.escape(item_anchor)}\s*/, "")
          end

          # Check for alias in array item
          if content.start_with?("*")
            unless aliases
              raise ArgumentError, "YAML aliases are not allowed"
            end
            alias_name = content[1..-1].strip
            res << anchors[alias_name]
          elsif content.empty?
            # Empty array item - check if next line is nested content or a new item
            item_value = if lines.any? && lines[0][/^ */].size > indent
              parse_any(lines, indent, permitted_tags, aliases, anchors)
            end
            anchors[item_anchor] = item_value if item_anchor
            res << item_value
          elsif content.start_with?("!ruby/object:")
            tag = content.strip
            unless permitted_tags.include?(tag)
              raise ArgumentError, "Disallowed class: #{tag}"
            end
            nested = parse_any(lines, indent, permitted_tags, aliases, anchors)
            item_value = if nested.is_a?(Hash)
              nested[:tag] = tag
              nested
            else
              { :tag => tag, "value" => nested }
            end
            anchors[item_anchor] = item_value if item_anchor
            res << item_value
          elsif content.start_with?("-")
            lines.unshift(" " * (indent + 2) + content)
            item_value = parse_any(lines, indent, permitted_tags, aliases, anchors)
            anchors[item_anchor] = item_value if item_anchor
            res << item_value
          elsif content =~ /^((?:[^#:]|:[^ ])+):(?:[ ]+(.*))?$/ && !content.start_with?("!ruby/object:")
            lines.unshift(" " * (indent + 2) + content)
            item_value = parse_any(lines, indent, permitted_tags, aliases, anchors)
            anchors[item_anchor] = item_value if item_anchor
            res << item_value
          elsif content.start_with?("|")
            modifier = content[1..-1].to_s.strip
            item_value = parse_block_scalar(lines, indent, modifier)
            anchors[item_anchor] = item_value if item_anchor
            res << item_value
          else
            str = unquote_simple(content)
            while lines.any? && !lines[0].strip.empty? && lines[0][/^ */].size > indent
              str << " " << lines.shift.strip
            end
            anchors[item_anchor] = str if item_anchor
            res << str
          end
        end
        result = res
      elsif line.lstrip =~ /^((?:[^#:]|:[^ ])+):(?:[ ]+(.*))?$/ && !line.lstrip.start_with?("!ruby/object:")
        res = Hash.new
        while lines.any? && lines[0][/^ */].size == indent && lines[0].lstrip =~ /^((?:[^#:]|:[^ ])+):(?:[ ]+(.*))?$/ && !lines[0].lstrip.start_with?("!ruby/object:")
          l = lines.shift
          l.lstrip =~ /^((?:[^#:]|:[^ ])+):(?:[ ]+(.*))?$/
          key = $1.strip
          val = $2.to_s.strip
          val = strip_comment(val)

          # Check for anchor in value
          val_anchor = nil
          if val =~ /^&(\S+)\s+/
            unless aliases
              raise ArgumentError, "YAML aliases are not allowed"
            end
            val_anchor = $1
            val = val.sub(/^&#{Regexp.escape(val_anchor)}\s+/, "")
          end

          # Check for alias in value
          if val.start_with?("*")
            unless aliases
              raise ArgumentError, "YAML aliases are not allowed"
            end
            alias_name = val[1..-1].strip
            res[key] = anchors[alias_name]
          elsif val.start_with?("!ruby/object:")
            tag = val.strip
            unless permitted_tags.include?(tag)
              raise ArgumentError, "Disallowed class: #{tag}"
            end
            nested = parse_any(lines, indent, permitted_tags, aliases, anchors)
            value = if nested.is_a?(Hash)
              nested[:tag] = tag
              nested
            else
              { :tag => tag, "value" => nested }
            end
            anchors[val_anchor] = value if val_anchor
            res[key] = value
          elsif val.empty?
            value = if lines.any? && (lines[0].lstrip.start_with?("- ") || lines[0].lstrip == "-") && lines[0][/^ */].size == indent
              parse_any(lines, indent, permitted_tags, aliases, anchors)
            else
              parse_any(lines, indent + 1, permitted_tags, aliases, anchors)
            end
            anchors[val_anchor] = value if val_anchor
            res[key] = value
          elsif val == "[]"
            value = []
            anchors[val_anchor] = value if val_anchor
            res[key] = value
          elsif val == "{}"
            value = {}
            anchors[val_anchor] = value if val_anchor
            res[key] = value
          elsif val.start_with?("|")
            modifier = val[1..-1].to_s.strip
            value = parse_block_scalar(lines, indent, modifier)
            anchors[val_anchor] = value if val_anchor
            res[key] = value
          else
            str = unquote_simple(val)
            while lines.any? && !lines[0].strip.empty? && lines[0][/^ */].size > indent
              str << " " << lines.shift.strip
            end
            anchors[val_anchor] = str if val_anchor
            res[key] = str
          end
        end
        result = res
      elsif line.lstrip.start_with?("!ruby/object:")
        tag = lines.shift.lstrip.strip
        unless permitted_tags.include?(tag)
          raise ArgumentError, "Disallowed class: #{tag}"
        end
        nested = parse_any(lines, indent, permitted_tags, aliases, anchors)
        if nested.is_a?(Hash)
          nested[:tag] = tag
          result = nested
        else
          result = { :tag => tag, "value" => nested }
        end
      elsif line.lstrip.start_with?("|")
        modifier = line.lstrip[1..-1].to_s.strip
        lines.shift
        result = parse_block_scalar(lines, indent, modifier)
      else
        str = unquote_simple(lines.shift.strip)
        while lines.any? && !lines[0].strip.empty? && lines[0][/^ */].size > indent
          str << " " << lines.shift.strip
        end
        result = str
      end

      # Store anchor if present
      anchors[anchor_name] = result if anchor_name
      result
    end

    def parse_block_scalar(lines, base_indent, modifier)
      parts = []
      block_indent = nil
      while lines.any?
        if lines[0].strip.empty?
          parts << "\n"
          lines.shift
        else
          line_indent = lines[0][/^ */].size
          break if line_indent <= base_indent
          block_indent ||= line_indent
          l = lines.shift
          parts << l[block_indent..-1].to_s << "\n"
        end
      end
      res = parts.join
      res.chomp! if modifier == "-" && res.end_with?("\n")
      res
    end

    def build_permitted_tags(permitted_classes)
      Array(permitted_classes).map do |klass|
        name = klass.is_a?(Module) ? klass.name : klass.to_s
        "!ruby/object:#{name}"
      end
    end

    def convert_to_spec(hash, permitted_symbols)
      spec = Gem::Specification.allocate
      return spec unless hash.is_a?(Hash)

      converted_hash = {}
      hash.each {|k, v| converted_hash[k] = convert_any(v, permitted_symbols) }

      # Ensure specification_version is an Integer if it's a valid numeric string
      if converted_hash["specification_version"] && !converted_hash["specification_version"].is_a?(Integer)
        val = converted_hash["specification_version"]
        if val.is_a?(String) && /\A\d+\z/.match?(val)
          converted_hash["specification_version"] = val.to_i
        end
      end

      # Debug: log rdoc_options that contain non-string elements
      if converted_hash["rdoc_options"] && converted_hash["name"]
        rdoc_opts = converted_hash["rdoc_options"]
        has_non_string = case rdoc_opts
                         when Array then rdoc_opts.any? {|o| !o.is_a?(String) }
                         when Hash then true
                         else true
        end
        if has_non_string
          warn "[DEBUG rdoc_options] gem=#{converted_hash["name"]} class=#{rdoc_opts.class} value=#{rdoc_opts.inspect}"
        end
      end

      # Ensure rdoc_options is an Array of Strings
      if converted_hash["rdoc_options"].is_a?(Hash)
        converted_hash["rdoc_options"] = converted_hash["rdoc_options"].values.flatten.compact.map(&:to_s)
      elsif converted_hash["rdoc_options"].is_a?(Array)
        converted_hash["rdoc_options"] = converted_hash["rdoc_options"].flat_map do |opt|
          if opt.is_a?(Hash)
            opt.flat_map {|k, v| [k.to_s, v.to_s] }
          elsif opt.is_a?(String)
            opt
          else
            opt.to_s
          end
        end
      end

      # Ensure other array fields are properly typed
      ["files", "test_files", "executables", "requirements", "extra_rdoc_files"].each do |field|
        if converted_hash[field].is_a?(Hash)
          converted_hash[field] = converted_hash[field].values.flatten.compact
        elsif !converted_hash[field].is_a?(Array) && converted_hash[field]
          converted_hash[field] = [converted_hash[field]].flatten.compact
        end
      end

      spec.yaml_initialize("!ruby/object:Gem::Specification", converted_hash)
      spec
    end

    def convert_any(obj, permitted_symbols)
      if obj.is_a?(Hash)
        if obj[:tag] == "!ruby/object:Gem::Version"
          ver = obj["version"] || obj["value"]
          Gem::Version.new(ver.to_s)
        elsif obj[:tag] == "!ruby/object:Gem::Platform"
          if obj["value"]
            Gem::Platform.new(obj["value"])
          else
            Gem::Platform.new([obj["cpu"], obj["os"], obj["version"]])
          end
        elsif ["!ruby/object:Gem::Requirement", "!ruby/object:Gem::Version::Requirement"].include?(obj[:tag])
          r = Gem::Requirement.allocate
          raw_reqs = obj["requirements"] || obj["value"]
          reqs = convert_any(raw_reqs, permitted_symbols)
          # Ensure reqs is an array (never nil or Hash)
          reqs = [] unless reqs.is_a?(Array)
          if reqs.is_a?(Array) && !reqs.empty?
            safe_reqs = []
            reqs.each do |item|
              if item.is_a?(Array) && item.size == 2
                op = item[0].to_s
                ver = item[1]
                # Validate that op is a valid requirement operator
                if ["=", "!=", ">", "<", ">=", "<=", "~>"].include?(op)
                  version_obj = if ver.is_a?(Gem::Version)
                    ver
                  else
                    Gem::Version.new(ver.to_s)
                  end
                  safe_reqs << [op, version_obj]
                end
              elsif item.is_a?(String)
                # Try to validate the requirement string
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
        elsif obj[:tag] == "!ruby/object:Gem::Dependency"
          d = Gem::Dependency.allocate
          d.instance_variable_set(:@name, obj["name"])

          # Ensure requirement is properly formed
          requirement = begin
            converted_req = convert_any(obj["requirement"], permitted_symbols)
            # Validate that the requirement has valid requirements
            if converted_req.is_a?(Gem::Requirement)
              # Check if the requirement has any invalid items
              reqs = converted_req.instance_variable_get(:@requirements)
              if reqs&.is_a?(Array)
                # Verify all requirements are valid
                valid = reqs.all? do |item|
                  next true if item == Gem::Requirement::DefaultRequirement
                  if item.is_a?(Array) && item.size >= 2
                    ["=", "!=", ">", "<", ">=", "<=", "~>"].include?(item[0].to_s)
                  else
                    false
                  end
                end
                valid ? converted_req : Gem::Requirement.default
              else
                converted_req
              end
            else
              converted_req
            end
          rescue StandardError
            Gem::Requirement.default
          end

          d.instance_variable_set(:@requirement, requirement)

          type = obj["type"]
          if type
            type = type.to_s.sub(/^:/, "").to_sym
          else
            type = :runtime
          end
          if permitted_symbols.any? && !permitted_symbols.include?(type.to_s)
            raise ArgumentError, "Disallowed symbol: #{type.inspect}"
          end
          d.instance_variable_set(:@type, type)

          d.instance_variable_set(:@prerelease, ["true", true].include?(obj["prerelease"]))
          d.instance_variable_set(:@version_requirements, d.instance_variable_get(:@requirement))
          d
        else
          res = Hash.new
          obj.each do |k, v|
            next if k == :tag
            key_str = k.to_s
            converted_val = convert_any(v, permitted_symbols)

            # Convert Hash to Array for fields that should be arrays
            if ["rdoc_options", "files", "test_files", "executables", "requirements", "extra_rdoc_files"].include?(key_str)
              if converted_val.is_a?(Hash)
                converted_val = converted_val.values.flatten.compact
              elsif !converted_val.is_a?(Array) && converted_val
                converted_val = [converted_val].flatten.compact
              end
            end

            res[key_str] = converted_val
          end
          res
        end
      elsif obj.is_a?(Array)
        obj.map {|i| convert_any(i, permitted_symbols) }
      else
        obj
      end
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
          when "'"
            in_single = true
          when '"'
            in_double = true
          when "#"
            return val[0...i].rstrip
          end
        end
      end

      val
    end

    def unquote_simple(val)
      # Strip YAML non-specific tag (! prefix), e.g. ! '>=' -> '>='
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
        {}
      elsif val =~ /^\[(.*)\]$/
        inner = $1.strip
        return [] if inner.empty?
        inner.split(/\s*,\s*/).reject(&:empty?).map {|element| unquote_simple(element) }
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
  end
end
