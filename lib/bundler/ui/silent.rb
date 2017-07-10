# frozen_string_literal: true
module Bundler
  module UI
    class Silent
      def initialize
        @warnings = []
      end

      def add_color(string, color)
        string
      end

      def info(message, newline = nil)
      end

      def confirm(message, newline = nil)
      end

      def warn(message, newline = nil)
        @warnings |= [message]
      end

      def error(message, newline = nil)
      end

      def debug(message, newline = nil)
      end

      def debug?
        false
      end

      def quiet?
        false
      end

      def ask(message)
      end

      def level=(name)
      end

      def level(name = nil)
      end

      def trace(message, newline = nil)
      end

      def silence
        yield
      end

      def unprinted_warnings
        @warnings
      end
    end
  end
end
