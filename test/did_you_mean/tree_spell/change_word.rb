module TreeSpell
  # Changes a word with one of four actions:
  # insertion, substitution, deletion and transposition.
  class ChangeWord
    # initialize with input string
    def initialize(input)
      @input = input
      @len = input.length
    end

    # insert char after index of i_place
    def insertion(i_place, char)
      @word = input.dup
      return char + word if i_place == 0
      return word + char if i_place == len - 1
      word.insert(i_place + 1, char)
    end

    # substitute char at index of i_place
    def substitution(i_place, char)
      @word = input.dup
      word[i_place] = char
      word
    end

    # delete character at index of i_place
    def deletion(i_place)
      @word = input.dup
      word.slice!(i_place)
      word
    end

    # transpose char at i_place with char at i_place + direction
    # if i_place + direction is out of bounds just swap in other direction
    def transposition(i_place, direction)
      @word = input.dup
      w = word.dup
      return  swap_first_two(w) if i_place + direction < 0
      return  swap_last_two(w) if i_place + direction >= len
      swap_two(w, i_place, direction)
      w
    end

    private

    attr_accessor :word, :input, :len

    def swap_first_two(w)
      w[1] + w[0] + word[2..-1]
    end

    def swap_last_two(w)
      w[0...(len - 2)] + word[len - 1] + word[len - 2]
    end

    def swap_two(w, i_place, direction)
      w[i_place] = word[i_place + direction]
      w[i_place + direction] = word[i_place]
    end
  end
end
