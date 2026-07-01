# frozen_string_literal: true

module SyntaxSuggest
  # SyntaxSuggest.module_for_detailed_message [Private]
  #
  # Used to monkeypatch SyntaxError via Module.prepend
  def self.module_for_detailed_message
    Module.new {
      def detailed_message(highlight: true, syntax_suggest: true, **kwargs)
        return super unless syntax_suggest

        require "syntax_suggest/api" unless defined?(SyntaxSuggest::DEFAULT_VALUE)

        message = super

        if path
          file = Pathname.new(path)
          io = SyntaxSuggest::MiniStringIO.new

          SyntaxSuggest.call(
            io: io,
            source: file.read,
            filename: file,
            terminal: highlight
          )
          annotation = io.string

          annotation += "\n" unless annotation.end_with?("\n")

          annotation + message
        else
          message
        end
      rescue => e
        if ENV["SYNTAX_SUGGEST_DEBUG"]
          $stderr.warn(e.message)
          $stderr.warn(e.backtrace)
        end

        # Ignore internal errors
        message
      end
    }
  end
end

SyntaxError.prepend(SyntaxSuggest.module_for_detailed_message)
