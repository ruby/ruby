# frozen_string_literal: true

module IRB
  module Command
    class Copy < Base
      category "Misc"
      description "Copy expression output to clipboard"

      help_message(<<~HELP)
        Usage: copy ([expression])

        When given:
        - an expression, copy the inspect result of the expression to the clipboard.
        - no arguments, copy the last evaluated result (`_`) to the clipboard.

        Examples:

          copy Foo.new
          copy User.all.to_a
          copy
      HELP

      def execute(arg)
        # Copy last value if no expression was supplied
        arg = '_' if arg.to_s.strip.empty?

        value = irb_context.workspace.binding.eval(arg)
        output = irb_context.inspect_method.inspect_value(value, +'', colorize: false).chomp

        if clipboard_available?
          copy_to_clipboard(output)
        else
          warn "System clipboard not found"
        end
      rescue StandardError => e
        warn "Error: #{e}"
      end

      private

      def copy_to_clipboard(text)
        IO.popen(clipboard_program, 'w') do |io|
          io.write(text)
        end

        raise IOError.new("Copying to clipboard failed") unless $? == 0

        puts "Copied to system clipboard"
      rescue Errno::ENOENT => e
        warn e.message
        warn "Is IRB.conf[:COPY_COMMAND] set to a bad value?"
      end

      def clipboard_program
        @clipboard_program ||= if IRB.conf[:COPY_COMMAND]
                                 IRB.conf[:COPY_COMMAND]
                               elsif executable?("pbcopy")
                                 "pbcopy"
                               elsif executable?("xclip")
                                 "xclip -selection clipboard"
                               end
      end

      def executable?(command)
        system("which #{command} > /dev/null 2>&1")
      end

      def clipboard_available?
        !!clipboard_program
      end
    end
  end
end
