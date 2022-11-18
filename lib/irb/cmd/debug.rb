require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Debug < Nop
      BINDING_IRB_FRAME_REGEXPS = [
        '<internal:prelude>',
        binding.method(:irb).source_location.first,
      ].map { |file| /\A#{Regexp.escape(file)}:\d+:in `irb'\z/ }
      IRB_DIR = File.expand_path('..', __dir__)

      def execute(*args)
        unless binding_irb?
          puts "`debug` command is only available when IRB is started with binding.irb"
          return
        end

        unless setup_debugger
          puts <<~MSG
            You need to install the debug gem before using this command.
            If you use `bundle exec`, please add `gem "debug"` into your Gemfile.
          MSG
          return
        end

        # To make debugger commands like `next` or `continue` work without asking
        # the user to quit IRB after that, we need to exit IRB first and then hit
        # a TracePoint on #debug_break.
        file, lineno = IRB::Irb.instance_method(:debug_break).source_location
        DEBUGGER__::SESSION.add_line_breakpoint(file, lineno + 1, oneshot: true, hook_call: false)
        # exit current Irb#run call
        throw :IRB_EXIT
      end

      private

      def binding_irb?
        caller.any? do |frame|
          BINDING_IRB_FRAME_REGEXPS.any? do |regexp|
            frame.match?(regexp)
          end
        end
      end

      def setup_debugger
        unless defined?(DEBUGGER__::SESSION)
          begin
            require "debug/session"
          rescue LoadError
            return false
          end
          DEBUGGER__.start(nonstop: true)
        end

        unless DEBUGGER__.respond_to?(:capture_frames_without_irb)
          DEBUGGER__.singleton_class.send(:alias_method, :capture_frames_without_irb, :capture_frames)

          def DEBUGGER__.capture_frames(*args)
            frames = capture_frames_without_irb(*args)
            frames.reject! do |frame|
              frame.realpath&.start_with?(IRB_DIR) || frame.path == "<internal:prelude>"
            end
            frames
          end
        end

        true
      end
    end
  end
end
