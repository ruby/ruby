# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Logger
    # @rbs (IO out) -> void
    def initialize(out = STDERR)
      @out = out
    end

    # @rbs (String message) -> void
    def warn(message)
      @out << message << "\n"
    end

    # @rbs (String message) -> void
    def error(message)
      @out << message << "\n"
    end
  end
end
