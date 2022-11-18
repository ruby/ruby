require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Debug < Nop
      def execute(*args)
        require "debug/session"
        DEBUGGER__.start(nonstop: true)
        DEBUGGER__.singleton_class.send(:alias_method, :original_capture_frames, :capture_frames)

        def DEBUGGER__.capture_frames(skip_path_prefix)
          frames = original_capture_frames(skip_path_prefix)
          frames.reject! do |frame|
            frame.realpath&.start_with?(::IRB::Irb::DIR_NAME) || frame.path.match?(/internal:prelude/)
          end
          frames
        end

        file, lineno = IRB::Irb.instance_method(:debug_break).source_location
        DEBUGGER__::SESSION.add_line_breakpoint(file, lineno + 1, oneshot: true, hook_call: false)
        # exit current Irb#run call
        throw :IRB_EXIT
      rescue LoadError => e
        puts <<~MSG
          You need to install the debug gem before using this command.
          If you use `bundle exec`, please add `gem "debug"` into your Gemfile.
        MSG
      end
    end
  end
end
