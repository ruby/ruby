# frozen_string_literal: true

module Gem
  module YAMLSerializer
    class Parser
      # A plain (unquoted) mapping key followed by ":". "#" inside a key is
      # literal unless preceded by a space (which would start a comment).
      # Like Psych, spaces and tabs may separate the ":" from the value.
      MAPPING_KEY_RE = /\G((?:[^#:\s]|:[^ \t])(?:[^#:]|:[^ \t]|(?<=[^ ])#)*):(?:[ \t]+(.*))?$/
      # A quoted mapping key followed by ":". A whole-line quoted scalar
      # cannot match because its closing quote is at the end of the line.
      QUOTED_KEY_RE = /\G("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'):(?:[ \t]+(.*))?$/
      # An entry of a flow sequence. A quoted entry may contain commas.
      FLOW_SEQUENCE_ENTRY_RE = /"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^,\s](?:[^,]*[^,\s])?/
      SEQUENCE_ENTRY_RE = /\G-(?: |\z)/
      # A quoted scalar whose closing quote is on a later line.
      OPEN_QUOTED_RE = /\A(?:! )?(?:"(?>(?:[^"\\]|\\.)*)(\\)?|'(?>(?:[^']|'')*))\z/
      RUBY_OBJECT_TAG_RE = %r{\G!ruby/object:}
      LSTRIP_BYTES = [0, 9, 10, 11, 12, 13, 32].freeze
      UTF8_BOM_BYTES = [0xEF, 0xBB, 0xBF].freeze
      MAX_NESTING_DEPTH = 1_000
      NULL_SCALARS = %w[~ null].freeze
      BLANK_RE = /\A[\0\s]*\z/
      BLANK_OR_COMMENT_RE = /\A[\0\s]*(?:#|\z)/
      DOCUMENT_END_RE = /\A\.\.\.(?:[ \t]|\z)/
      DOCUMENT_START_RE = /\A---(?:[ \t]|\z)/

      STRING_UNESCAPES = {
        "\\\\" => "\\",
        "\\\"" => "\"",
        "\\ " => " ",
        "\\0" => "\0",
        "\\a" => "\a",
        "\\b" => "\b",
        "\\t" => "\t",
        "\\n" => "\n",
        "\\v" => "\v",
        "\\f" => "\f",
        "\\r" => "\r",
        "\\e" => "\e",
        "\\N" => "\u0085",
        "\\_" => "\u00A0",
        "\\L" => "\u2028",
        "\\P" => "\u2029",
      }.freeze

      def initialize(source)
        raise TypeError, "no implicit conversion of nil into String" if source.nil?

        source = strip_bom(source)
        # Keep trailing empty lines, which a block scalar with keep chomping
        # ("|+") preserves, but not the empty string after the final line
        # break.
        @lines = source.split(/\r?\n/, -1)
        @lines.pop if @lines.last == ""
        @lines.each(&:freeze)
        @anchors = {}
        @depth = 0
        strip_document_end
        strip_extra_documents
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

      # Byte-wise, as checksums.yaml is read as binary unlike config files,
      # and binary cannot be compared with a UTF-8 string holding the BOM.
      def strip_bom(source)
        return source unless UTF8_BOM_BYTES.each_with_index.all? {|byte, i| source.getbyte(i) == byte }

        source.byteslice(UTF8_BOM_BYTES.size..)
      end

      def strip_document_end
        index = @lines.index {|line| DOCUMENT_END_RE.match?(line) }
        @lines.slice!(index..) if index
      end

      def strip_extra_documents
        first_content_index = @lines.index {|line| !BLANK_OR_COMMENT_RE.match?(line) }
        return unless first_content_index

        if DOCUMENT_START_RE.match?(@lines[first_content_index])
          # Keep the opening marker; strip_document_prefix consumes it afterward.
          @lines.shift(first_content_index)
          search_start = 1
        else
          search_start = first_content_index
        end
        index = (search_start...@lines.size).find {|i| DOCUMENT_START_RE.match?(@lines[i]) }
        @lines.slice!(index..) if index
      end

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
        @depth += 1
        raise_max_nesting! if @depth > MAX_NESTING_DEPTH

        skip_blank_and_comments
        return nil if @lines.empty?

        line = @lines[0]
        indent = indent_of(line)
        return nil if indent < base_indent

        return parse_alias_ref if /\G\*/.match?(line, indent)

        pos = indent
        if /\G&/.match?(line, indent) && (anchor = consume_anchor)
          # A lone anchor line, e.g. "--- &1", anchors the node on the next line.
          skip_blank_and_comments
          return register_anchor(anchor, nil) if @lines.empty? || current_indent < base_indent
          line = @lines[0]
          indent = pos = indent_of(line)
        end

        if SEQUENCE_ENTRY_RE.match?(line, pos)
          parse_sequence(indent, anchor)
        elsif QUOTED_KEY_RE.match?(line, pos)
          # A mapping whose key is quoted, e.g. '"have: colon": value'.
          parse_mapping(indent, anchor)
        elsif (/\G"/.match?(line, pos) && line.end_with?("\"")) ||
              (/\G'/.match?(line, pos) && line.end_with?("'"))
          # A whole-line quoted scalar, e.g. '"system: foo: bar"'. It may
          # contain ": ", so it must be checked before MAPPING_KEY_RE.
          parse_plain_scalar(indent, anchor)
        elsif MAPPING_KEY_RE.match?(line, pos) && !RUBY_OBJECT_TAG_RE.match?(line, pos)
          parse_mapping(indent, anchor)
        elsif RUBY_OBJECT_TAG_RE.match?(line, pos)
          parse_tagged_node(indent, anchor)
        elsif /\G\|/.match?(line, pos)
          modifier = line[pos + 1, line.size].strip
          @lines.shift
          register_anchor(anchor, Scalar.new(parse_block_scalar(indent, modifier)))
        else
          parse_plain_scalar(indent, anchor)
        end
      ensure
        @depth -= 1
      end

      def parse_sequence(indent, anchor)
        items = []
        while @lines.any?
          skip_blank_and_comments
          break if @lines.empty?
          line = @lines[0]
          break unless indent_of(line) == indent && SEQUENCE_ENTRY_RE.match?(line, indent)
          @lines.shift
          content = line[indent + 1, line.size]
          content.strip!
          item_anchor = nil
          item_anchor, content = extract_anchor(content) if content.start_with?("&")
          item = parse_sequence_item(content, indent)
          items << register_anchor(item_anchor, item)
        end
        register_anchor(anchor, Sequence.new(items))
      end

      def parse_sequence_item(content, indent)
        if content.start_with?("*")
          parse_inline_alias(content)
        elsif content.empty?
          skip_blank_and_comments
          @lines.any? && current_indent > indent ? parse_node(indent + 1) : nil
        elsif content.start_with?("!ruby/object:")
          parse_tagged_content(content.strip, indent)
        elsif content.start_with?("!binary ")
          parse_binary_value(content, indent)
        elsif content.start_with?("-")
          @lines.unshift("#{" " * (indent + 2)}#{content}")
          parse_node(indent)
        elsif QUOTED_KEY_RE.match?(content) ||
              (MAPPING_KEY_RE.match?(content) && !content.start_with?("!ruby/object:") &&
               !OPEN_QUOTED_RE.match?(content))
          @lines.unshift("#{" " * (indent + 2)}#{content}")
          parse_node(indent)
        elsif content.start_with?("|")
          Scalar.new(parse_block_scalar(indent, content[1..].to_s.strip))
        else
          parse_inline_scalar(content, indent)
        end
      end

      def parse_mapping(indent, anchor)
        pairs = []
        while @lines.any?
          skip_blank_and_comments
          break if @lines.empty?
          line = @lines[0]
          break unless indent_of(line) == indent

          if (match = QUOTED_KEY_RE.match(line, indent))
            key = coerce(match[1])
          elsif (match = MAPPING_KEY_RE.match(line, indent)) && !RUBY_OBJECT_TAG_RE.match?(line, indent)
            key = match[1]
            key.strip!
            key = decode_binary_tag(key) if key.start_with?("!binary ")
          else
            break
          end
          @lines.shift
          val = match[2]
          val&.strip!
          val = strip_comment(val || "")

          val_anchor = nil
          val_anchor, val = extract_anchor(val) if val.start_with?("&")
          value = parse_mapping_value(val, indent)
          value = register_anchor(val_anchor, value) if val_anchor

          pairs << key << value
        end
        register_anchor(anchor, Mapping.new(pairs))
      end

      def parse_mapping_value(val, indent)
        if val.start_with?("*")
          parse_inline_alias(val)
        elsif val.start_with?("!ruby/object:")
          parse_tagged_content(val.strip, indent)
        elsif val.start_with?("!binary ")
          parse_binary_value(val, indent)
        elsif val.empty?
          skip_blank_and_comments
          line = @lines[0]
          if line && indent_of(line) == indent && SEQUENCE_ENTRY_RE.match?(line, indent)
            parse_node(indent)
          else
            parse_node(indent + 1)
          end
        elsif val == "[]"
          Sequence.new([])
        elsif val == "{}"
          Mapping.new([])
        elsif val.start_with?("|")
          Scalar.new(parse_block_scalar(indent, val[1..].to_s.strip))
        else
          parse_inline_scalar(val, indent)
        end
      end

      def parse_tagged_node(indent, anchor)
        tag = @lines.shift.strip
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
          Mapping.new(["value", node], tag, anchor)
        end
      end

      def parse_block_scalar(base_indent, modifier)
        parts = []
        indentation = modifier[/\A[+-]?([1-9])/, 1]
        chomping = modifier[/\A[1-9]?([+-])/, 1]
        block_indent = indentation && base_indent + indentation.to_i

        while @lines.any?
          line = @lines[0]
          if BLANK_RE.match?(line)
            parts << line[block_indent..] if block_indent && line.size > block_indent
            parts << "\n"
            @lines.shift
          else
            line_indent = indent_of(line)
            break if line_indent <= base_indent
            block_indent ||= line_indent
            parts << @lines.shift[block_indent..].to_s << "\n"
          end
        end

        res = parts.join
        unless chomping == "+"
          res.delete_suffix!("\n") while res.end_with?("\n")
          # Clipping keeps the final line break but drops trailing empty lines.
          res << "\n" if chomping.nil? && !res.empty?
        end
        res
      end

      def parse_plain_scalar(indent, anchor)
        val = @lines.shift.strip
        result = coerce(val)
        return register_anchor(anchor, result) if result.is_a?(Mapping) || result.is_a?(Sequence)

        fold_continuation_lines(result, val, indent)
        register_anchor(anchor, Scalar.new(result))
      end

      def parse_inline_scalar(val, indent)
        result = coerce(val)
        return result if result.is_a?(Mapping) || result.is_a?(Sequence)

        fold_continuation_lines(result, val, indent)
        Scalar.new(result)
      end

      def fold_continuation_lines(result, val, indent)
        return unless result.is_a?(String)

        return result.replace(fold_quoted_lines(val.delete_prefix("! "), indent)) if OPEN_QUOTED_RE.match?(val)

        while @lines.any? && !BLANK_OR_COMMENT_RE.match?(@lines[0]) && current_indent > indent
          result << " " << @lines.shift.strip
        end
      end

      def fold_quoted_lines(val, indent)
        open = OPEN_QUOTED_RE.match(val)
        breaks = +""
        while open && @lines.any? && (BLANK_RE.match?(@lines[0]) || current_indent > indent)
          line = @lines.shift.strip
          next breaks << "\n" if line.empty?

          val.chop! if open[1]
          val << (breaks.empty? && !open[1] ? " " : breaks) << line
          breaks.clear
          open = OPEN_QUOTED_RE.match("#{val[0]}#{line}")
        end
        coerce(val)
      end

      def coerce(val, depth = 0)
        raise_max_nesting! if depth > MAX_NESTING_DEPTH

        val = val.sub(/^! /, "") if val.start_with?("! ")

        if val.size >= 2 && val.start_with?("\"") && val.end_with?("\"")
          inner = val[1..-2]
          return inner unless inner.include?("\\")
          inner.gsub(/\\(?:["\\ 0abtnvfreN_LP]|x\h{2}|u\h{4}|U\h{8})/) do |m|
            char = STRING_UNESCAPES[m] || unescape_code_point(m)
            # Metadata is read as binary, where non-ASCII text stays as UTF-8 bytes.
            Encoding.compatible?(inner, char) ? char : char.b
          end
        elsif val.size >= 2 && val.start_with?("'") && val.end_with?("'")
          inner = val[1..-2]
          inner.include?("''") ? inner.gsub("''", "'") : inner
        elsif val == "true"
          true
        elsif val == "false"
          false
        elsif NULL_SCALARS.include?(val)
          nil
        elsif val == "{}"
          Mapping.new([])
        elsif val =~ /^\[(.*)\]$/
          inner = $1.strip
          return Sequence.new([]) if inner.empty?
          items = inner.scan(FLOW_SEQUENCE_ENTRY_RE).map {|e| Scalar.new(coerce(e, depth + 1)) }
          Sequence.new(items)
        elsif /\A\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}:\d{2})?/.match?(val)
          begin
            Time.new(val)
          rescue ArgumentError
            # date-only format like "2024-06-15" is not supported by Time.new
            if /\A(\d{4})-(\d{2})-(\d{2})\z/.match(val)
              Time.utc($1.to_i, $2.to_i, $3.to_i)
            else
              val
            end
          end
        elsif /^-?\d+$/.match?(val)
          val.to_i
        else
          val
        end
      end

      def unescape_code_point(escape)
        code = escape[2..].hex
        return escape if code > 0x10FFFF || code.between?(0xD800, 0xDFFF)
        code.chr(Encoding::UTF_8)
      end

      def decode_binary_tag(str)
        content = str.sub(/\A!binary\s+/, "")
        content = $1 if content =~ /\A"(.*)"\z/ || content =~ /\A'(.*)'\z/
        content.unpack1("m")
      end

      def parse_binary_value(val, indent)
        rest = val.sub(/\A!binary\s+/, "")
        if rest.start_with?("|")
          content = parse_block_scalar(indent, rest[1..].to_s.strip)
          Scalar.new(content.unpack1("m"))
        else
          Scalar.new(decode_binary_tag(val))
        end
      end

      def parse_alias_ref
        AliasRef.new(@lines.shift.lstrip[1..].strip)
      end

      def parse_inline_alias(content)
        AliasRef.new(content[1..].strip)
      end

      def current_indent
        indent_of(@lines[0])
      end

      def indent_of(line)
        i = 0
        i += 1 while LSTRIP_BYTES.include?(line.getbyte(i))
        i
      end

      def consume_anchor
        line = @lines[0]
        stripped = line.lstrip
        return nil unless stripped.start_with?("&") && stripped =~ /^&(\S+)\s*/

        anchor = $1
        if $'.empty?
          @lines.shift
        else
          @lines[0] = line.sub(/&#{Regexp.escape(anchor)}\s+/, "")
        end
        anchor
      end

      def extract_anchor(content)
        return [nil, content] unless content =~ /^&(\S+)/

        anchor = $1
        [anchor, content.sub(/^&#{Regexp.escape(anchor)}\s*/, "")]
      end

      def register_anchor(name, node)
        if name
          # An anchored empty node still defines the anchor, as a null.
          node ||= Scalar.new(nil)
          @anchors[name] = node
          node.anchor = name if node.respond_to?(:anchor=)
        end
        node
      end

      def raise_max_nesting!
        message = "exceeded maximum nesting depth (#{MAX_NESTING_DEPTH})"
        if defined?(Psych::VERSION)
          raise Psych::SyntaxError.new(nil, 0, 0, 0, message, nil)
        else
          raise Psych::SyntaxError, message
        end
      end

      def skip_blank_and_comments
        @lines.shift while @lines.any? && BLANK_OR_COMMENT_RE.match?(@lines[0])
      end

      def strip_comment(val)
        return val unless val.include?("#")
        return "" if val.lstrip.start_with?("#")

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
            when "#"
              # A "#" starts a comment only when preceded by whitespace.
              return val[0...i].rstrip if [" ", "\t"].include?(val[i - 1])
            end
          end
        end

        val
      end
    end
  end
end
