# frozen_string_literal: true

module Gem
  module YAMLSerializer
    class Emitter
      STRING_ESCAPES = {
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\0" => "\\0",
        "\a" => "\\a",
        "\b" => "\\b",
        "\t" => "\\t",
        "\n" => "\\n",
        "\v" => "\\v",
        "\f" => "\\f",
        "\r" => "\\r",
        "\e" => "\\e",
      }.freeze

      def emit(obj)
        res = "---#{emit_node(obj, 0)}"
        res << "...\n" if @open_ended
        res
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
        when NilClass
          "\n"
        when Numeric, Symbol, TrueClass, FalseClass
          " #{obj.inspect}\n"
        else
          " #{quote_string(obj.to_s)}\n"
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
          "#{pad(indent)}cpu:#{emit_node(plat.cpu, indent + 2)}" \
          "#{pad(indent)}os:#{emit_node(plat.os, indent + 2)}" \
          "#{pad(indent)}version:#{emit_node(plat.version, indent + 2)}"
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
            key_str = quote_string(key_str) if !is_symbol && needs_quoting?(key_str, key: true)
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
        # A CR cannot be represented in a block scalar because parsing
        # normalizes CRLF line breaks to LF, so quote and escape instead.
        if str.include?("\n") && !str.include?("\r")
          emit_block_scalar(str, indent)
        elsif needs_quoting?(str, quote)
          " #{quote_string(str)}\n"
        else
          " #{str}\n"
        end
      end

      def emit_block_scalar(str, indent)
        # The root node has no parent to be indented from, so indent its
        # content by one level like libyaml does.
        indent = 2 if indent.zero?
        parts = [" |#{block_scalar_header(str)}\n"]
        str.each_line do |line|
          parts << (line == "\n" ? line : "#{pad(indent)}#{line}")
        end
        res = parts.join
        res << "\n" unless res.end_with?("\n")
        res
      end

      # Mirrors libyaml: an explicit indentation indicator when the first
      # line is empty or starts with a space (a parser would otherwise take
      # that whitespace as the block indentation and drop it), "-" when the
      # content does not end with a line break and "+" when it ends with
      # more than one, which also requires a document end marker.
      def block_scalar_header(str)
        header = +""
        header << "2" if str.start_with?(" ", "\n")
        if !str.end_with?("\n")
          header << "-"
        elsif str.end_with?("\n\n") || str == "\n"
          header << "+"
          @open_ended = true
        end
        header
      end

      def needs_quoting?(str, quote = false, key: false)
        quote || str.empty? || str != str.strip || str =~ /[[:cntrl:]]/ ||
          str =~ /^[!*&:@%$"'|`]/ || str =~ /^-?\d+(\.\d+)?$/ || str =~ /^[<>=-]/ ||
          str == "true" || str == "false" || str == "nil" || str == "null" || str == "~" ||
          (key ? colon_needs_quoting_in_key?(str) : str.include?(":")) ||
          str.include?("#") || str.include?("[") || str.include?("]") ||
          str.include?("{") || str.include?("}") || str.include?(",")
      end

      # The serializer that RubyGems 4.0 and Bundler 4.0 ship keeps quotes as
      # part of a key, so keys like Bundler's mirror settings for a URL stay
      # plain where YAML allows it, as libyaml writes them. A ":" only ends a
      # plain key when a space or the line end follows it, and a key that
      # starts with a letter is not read as a number or a time.
      def colon_needs_quoting_in_key?(str)
        str.include?(":") && (!str.match?(/\A[[:alpha:]]/) || str.match?(/:(?!\S)/))
      end

      def quote_string(str)
        %("#{str.gsub(/[\\"]|[[:cntrl:]]/) {|c| STRING_ESCAPES[c] || format("\\x%02X", c.ord) }}")
      end

      def pad(indent)
        " " * indent
      end
    end
  end
end
