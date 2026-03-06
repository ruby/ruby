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

    ARRAY_REGEX = /
      ^
      (?:[ ]*-[ ]) # '- ' before array items
      (['"]?) # optional opening quote
      (.*) # value
      \1 # matching closing quote
      $
    /xo

    HASH_REGEX = /
      ^
      ([ ]*) # indentations
      ([^#]+) # key excludes comment char '#'
      (?::(?=(?:\s|$))) # :  (without the lookahead the #key includes this when : is present in value)
      [ ]?
      (['"]?) # optional opening quote
      (.*) # value
      \3 # matching closing quote
      $
    /xo

    def load(str)
      res = {}
      stack = [res]
      last_hash = nil
      last_empty_key = nil
      str.split(/\r?\n/) do |line|
        if match = HASH_REGEX.match(line)
          indent, key, quote, val = match.captures
          val = strip_comment(val)

          depth = indent.size / 2
          if quote.empty? && val.empty?
            new_hash = {}
            stack[depth][key] = new_hash
            stack[depth + 1] = new_hash
            last_empty_key = key
            last_hash = stack[depth]
          else
            val = [] if val == "[]" # empty array
            stack[depth][key] = val
          end
        elsif match = ARRAY_REGEX.match(line)
          _, val = match.captures
          val = strip_comment(val)

          last_hash[last_empty_key] = [] unless last_hash[last_empty_key].is_a?(Array)

          last_hash[last_empty_key].push(val)
        end
      end
      res
    end

    def strip_comment(val)
      if val.include?("#") && !val.start_with?("#")
        val.split("#", 2).first.strip
      else
        val
      end
    end
  end
end
