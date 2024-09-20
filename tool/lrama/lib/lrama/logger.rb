# frozen_string_literal: true

module Lrama
  class Logger
    def initialize(out = STDERR)
      @out = out
    end

    def warn(message)
      @out << message << "\n"
    end

    def error(message)
      @out << message << "\n"
    end
  end
end
