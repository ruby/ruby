# frozen_string_literal: false

require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Info < Nop
      def execute
        Class.new {
          def inspect
            str  = "Ruby version: #{RUBY_VERSION}\n"
            str += "IRB version: #{IRB.version}\n"
            str += "InputMethod: #{IRB.CurrentContext.io.inspect}\n"
            str += ".irbrc path: #{IRB.rc_file}\n" if File.exist?(IRB.rc_file)
            str += "RUBY_PLATFORM: #{RUBY_PLATFORM}\n"
            str
          end
          alias_method :to_s, :inspect
        }.new
      end
    end
  end
end
# :startdoc:
