module DidYouMean
  # spell checker for a dictionary that has a tree
  # structure, see doc/tree_spell_checker_api.md
  class TreeSpellChecker
    attr_reader :dictionary, :dimensions, :separator, :augment

    def initialize(dictionary:, separator: '/', augment: nil)
      @dictionary = dictionary
      @separator = separator
      @augment = augment
      @dimensions = parse_dimensions
    end

    def correct(input)
      plausibles = plausible_dimensions input
      return no_idea(input) if plausibles.empty?
      suggestions = find_suggestions input, plausibles
      return no_idea(input) if suggestions.empty?
      suggestions
    end

    private

    def parse_dimensions
      ParseDimensions.new(dictionary, separator).call
    end

    def find_suggestions(input, plausibles)
      states = plausibles[0].product(*plausibles[1..-1])
      paths = possible_paths states
      leaf = input.split(separator).last
      ideas = find_ideas(paths, leaf)
      ideas.compact.flatten
    end

    def no_idea(input)
      return [] unless augment
      ::DidYouMean::SpellChecker.new(dictionary: dictionary).correct(input)
    end

    def find_ideas(paths, leaf)
      paths.map do |path|
        names = find_leaves(path)
        ideas = CorrectElement.new.call names, leaf
        ideas_to_paths ideas, leaf, names, path
      end
    end

    def ideas_to_paths(ideas, leaf, names, path)
      return nil if ideas.empty?
      return [path + separator + leaf] if names.include? leaf
      ideas.map { |str| path + separator + str }
    end

    def find_leaves(path)
      dictionary.map do |str|
        next unless str.include? "#{path}#{separator}"
        str.gsub("#{path}#{separator}", '')
      end.compact
    end

    def possible_paths(states)
      states.map do |state|
        state.join separator
      end
    end

    def plausible_dimensions(input)
      elements = input.split(separator)[0..-2]
      elements.each_with_index.map do |element, i|
        next if dimensions[i].nil?
        CorrectElement.new.call dimensions[i], element
      end.compact
    end
  end

  # parses the elements in each dimension
  class ParseDimensions
    def initialize(dictionary, separator)
      @dictionary = dictionary
      @separator = separator
    end

    def call
      leafless = remove_leaves
      dimensions = find_elements leafless
      dimensions.map do |elements|
        elements.to_set.to_a
      end
    end

    private

    def remove_leaves
      dictionary.map do |a|
        elements = a.split(separator)
        elements[0..-2]
      end.to_set.to_a
    end

    def find_elements(leafless)
      max_elements = leafless.map(&:size).max
      dimensions = Array.new(max_elements) { [] }
      (0...max_elements).each do |i|
        leafless.each do |elements|
          dimensions[i] << elements[i] unless elements[i].nil?
        end
      end
      dimensions
    end

    attr_reader :dictionary, :separator
  end

  # identifies the elements close to element
  class CorrectElement
    def initialize
    end

    def call(names, element)
      return names if names.size == 1
      str = normalize element
      return [str] if names.include? str
      checker = ::DidYouMean::SpellChecker.new(dictionary: names)
      checker.correct(str)
    end

    private

    def normalize(leaf)
      str = leaf.dup
      str.downcase!
      return str unless str.include? '@'
      str.tr!('@', '  ')
    end
  end
end
