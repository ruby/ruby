# frozen_string_literal: true

module Bundler
  # A stub yaml serializer that can handle only hashes and strings (as of now).
  module YAMLSerializer
    module_function

    def dump(hash)
      yaml = String.new("---")
      yaml << dump_hash(hash)
    end

    def dump_hash(hash)
      yaml = String.new("\n")
      hash.each do |k, v|
        if k.is_a?(Symbol)
          yaml << ":#{k}:"
        else
          yaml << k << ":"
        end
        if v.is_a?(Hash)
          yaml << dump_hash(v).gsub(/^(?!$)/, "  ") # indent all non-empty lines
        elsif v.is_a?(Array) # Expected to be array of strings
          yaml << "\n- " << v.map {|s| s.to_s.gsub(/\s+/, " ").inspect }.join("\n- ") << "\n"
        else
          yaml << " " << v.to_s.gsub(/\s+/, " ").inspect << "\n"
        end
      end
      yaml
    end

    ARRAY_REGEX = /
      ^
      (?:[ ]*-[ ]) # '- ' before array items
      (['"]?) # optional opening quote
      (.*) # value
      \1 # matching closing quote
      $
    /xo.freeze

    HASH_REGEX = /
      ^
      ([ ]*) # indentations
      (.+) # key
      (?::(?=(?:\s|$))) # :  (without the lookahead the #key includes this when : is present in value)
      [ ]?
      (['"]?) # optional opening quote
      (.*) # value
      \3 # matching closing quote
      $
    /xo.freeze

    def load(str)
      res = {}
      stack = [res]
      last_hash = nil
      last_empty_key = nil
      str.split(/\r?\n/).each do |line|
        if match = HASH_REGEX.match(line)
          indent, key, quote, val = match.captures
          key = convert_to_backward_compatible_key(key)
          key = key[1..-1].to_sym if key.start_with?(":")
          depth = indent.scan(/  /).length
          if quote.empty? && val.empty?
            new_hash = {}
            stack[depth][key] = new_hash
            stack[depth + 1] = new_hash
            last_empty_key = key
            last_hash = stack[depth]
          else
            stack[depth][key] = convert_to_ruby_value(val)
          end
        elsif match = ARRAY_REGEX.match(line)
          _, val = match.captures
          last_hash[last_empty_key] = [] unless last_hash[last_empty_key].is_a?(Array)

          last_hash[last_empty_key].push(convert_to_ruby_value(val))
        end
      end
      res
    end

    def convert_to_ruby_value(val)
      if val.match?(/\A:(.*)\Z/)
        $1.to_sym
      elsif val.match?(/\A[+-]?\d+\Z/)
        val.to_i
      elsif val.match?(/\Atrue|false\Z/)
        val == "true"
      else
        val
      end
    end

    # for settings' keys
    def convert_to_backward_compatible_key(key)
      key = "#{key}/" if key =~ /https?:/i && key !~ %r{/\Z}
      key = key.gsub(".", "__") if key.include?(".")
      key
    end

    class << self
      private :dump_hash, :convert_to_backward_compatible_key
    end
  end
end
