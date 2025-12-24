# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Logger
    # @rbs (IO out) -> void
    def initialize(out = STDERR)
      @out = out
    end

    # @rbs () -> void
    def line_break
      @out << "\n"
    end

    # @rbs (String message) -> void
    def trace(message)
      @out << message << "\n"
    end

    # @rbs (String message) -> void
    def warn(message)
      @out << 'warning: ' << message << "\n"
    end

    # @rbs (String message) -> void
    def error(message)
      @out << 'error: ' << message << "\n"
    end
  end
end
