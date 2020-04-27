# frozen_string_literal: false

require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Info < Nop
      def execute
        Class.new {
          def inspect
            <<~EOM.chomp
              Ruby version: #{RUBY_VERSION}
              IRB version: #{IRB.version}
              InputMethod: #{IRB.CurrentContext.io.inspect}
              .irbrc path: #{IRB.rc_file}
            EOM
          end
          alias_method :to_s, :inspect
        }.new
      end
    end
  end
end
# :startdoc:
