# frozen_string_literal: true
require "bundler/vendored_thor"

module Bundler
  module UI
    class Shell
      LEVELS = %w(silent error warn confirm info debug).freeze

      attr_writer :shell

      def initialize(options = {})
        if options["no-color"] || !STDOUT.tty?
          Thor::Base.shell = Thor::Shell::Basic
        end
        @shell = Thor::Base.shell.new
        @level = ENV["DEBUG"] ? "debug" : "info"
        @warning_history = []
      end

      def add_color(string, *color)
        @shell.set_color(string, *color)
      end

      def info(msg, newline = nil)
        tell_me(msg, nil, newline) if level("info")
      end

      def confirm(msg, newline = nil)
        tell_me(msg, :green, newline) if level("confirm")
      end

      def warn(msg, newline = nil)
        return if @warning_history.include? msg
        @warning_history << msg
        tell_me(msg, :yellow, newline) if level("warn")
      end

      def error(msg, newline = nil)
        tell_me(msg, :red, newline) if level("error")
      end

      def debug(msg, newline = nil)
        tell_me(msg, nil, newline) if level("debug")
      end

      def debug?
        # needs to be false instead of nil to be newline param to other methods
        level("debug") ? true : false
      end

      def quiet?
        LEVELS.index(@level) <= LEVELS.index("warn")
      end

      def ask(msg)
        @shell.ask(msg)
      end

      def yes?(msg)
        @shell.yes?(msg)
      end

      def no?
        @shell.no?(msg)
      end

      def level=(level)
        raise ArgumentError unless LEVELS.include?(level.to_s)
        @level = level
      end

      def level(name = nil)
        name ? LEVELS.index(name) <= LEVELS.index(@level) : @level
      end

      def trace(e, newline = nil, force = false)
        return unless debug? || force
        msg = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n  ")}"
        tell_me(msg, nil, newline)
      end

      def silence(&blk)
        with_level("silent", &blk)
      end

      def unprinted_warnings
        []
      end

    private

      # valimism
      def tell_me(msg, color = nil, newline = nil)
        msg = word_wrap(msg) if newline.is_a?(Hash) && newline[:wrap]
        if newline.nil?
          @shell.say(msg, color)
        else
          @shell.say(msg, color, newline)
        end
      end

      def tell_err(message, color = nil, newline = nil)
        buffer = @shell.send(:prepare_message, message, *color)
        buffer << "\n" if newline && !message.to_s.end_with?("\n")

        @shell.send(:stderr).print(buffer)
        @shell.send(:stderr).flush
      end

      def strip_leading_spaces(text)
        spaces = text[/\A\s+/, 0]
        spaces ? text.gsub(/#{spaces}/, "") : text
      end

      def word_wrap(text, line_width = @shell.terminal_width)
        strip_leading_spaces(text).split("\n").collect do |line|
          line.length > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip : line
        end * "\n"
      end

      def with_level(level)
        original = @level
        @level = level
        yield
      ensure
        @level = original
      end
    end
  end
end
