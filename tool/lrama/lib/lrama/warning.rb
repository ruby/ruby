module Lrama
  class Warning
    attr_reader :errors, :warns

    def initialize(out = STDERR)
      @out = out
      @errors = []
      @warns = []
    end

    def error(message)
      @out << message << "\n"
      @errors << message
    end

    def warn(message)
      @out << message << "\n"
      @warns << message
    end

    def has_error?
      !@errors.empty?
    end
  end
end
