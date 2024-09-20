require_relative "../spell_checker"

module DidYouMean
  class PatternKeyNameChecker
    def initialize(no_matching_pattern_key_error)
      @key = no_matching_pattern_key_error.key
      @keys = no_matching_pattern_key_error.matchee.keys
    end

    def corrections
      @corrections ||= exact_matches.empty? ? SpellChecker.new(dictionary: @keys).correct(@key).map(&:inspect) : exact_matches
    end

    private

    def exact_matches
      @exact_matches ||= @keys.select { |word| @key == word.to_s }.map { |obj| format_object(obj) }
    end

    def format_object(symbol_or_object)
      if symbol_or_object.is_a?(Symbol)
        ":#{symbol_or_object}"
      else
        symbol_or_object.to_s
      end
    end
  end
end
