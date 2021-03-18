# frozen_string_literal: true

require_relative "nop"
require_relative "../color"

# :stopdoc:
module IRB
  module ExtendCommand
    class Ls < Nop
      def execute(*arg, grep: nil)
        o = Output.new(grep: grep)

        obj    = arg.empty? ? irb_context.workspace.main : arg.first
        locals = arg.empty? ? irb_context.workspace.binding.local_variables : []
        klass  = (obj.class == Class || obj.class == Module ? obj : obj.class)

        o.dump("constants", obj.constants) if obj.respond_to?(:constants)
        o.dump("#{klass}.methods", obj.singleton_methods(false))
        o.dump("#{klass}#methods", klass.public_instance_methods(false))
        o.dump("instance variables", obj.instance_variables)
        o.dump("class variables", klass.class_variables)
        o.dump("locals", locals)
      end

      class Output
        def initialize(grep: nil)
          @grep = grep
        end

        def dump(name, strs)
          strs = strs.grep(@grep) if @grep
          strs = strs.sort
          return if strs.empty?

          print "#{Color.colorize(name, [:BOLD, :BLUE])}: "
          if strs.size > 7
            len = [strs.map(&:length).max, 16].min
            puts; strs.each_slice(7) { |ss| puts "  #{ss.map { |s| "%-#{len}s" % s }.join("  ")}" }
          else
            puts strs.join("  ")
          end
        end
      end
      private_constant :Output
    end
  end
end
# :startdoc:
