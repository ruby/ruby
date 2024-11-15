module SyntaxSuggest
  # Mini String IO [Private]
  #
  # Acts like a StringIO with reduced API, but without having to require that
  # class.
  class MiniStringIO
    EMPTY_ARG = Object.new

    def initialize(isatty: $stderr.isatty)
      @string = +""
      @isatty = isatty
    end

    attr_reader :isatty
    def puts(value = EMPTY_ARG, **)
      if !value.equal?(EMPTY_ARG)
        @string << value
      end
      @string << $/
    end

    attr_reader :string
  end
end
