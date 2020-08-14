require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Measure < Nop
      def initialize(*args)
        super(*args)
      end

      def execute(type = nil, arg = nil)
        case type
        when :off
          IRB.conf[:MEASURE] = nil
          IRB.unset_measure_callback(arg)
        when :list
          IRB.conf[:MEASURE_CALLBACKS].each do |type_name, _|
            puts "- #{type_name}"
          end
        when :on
          IRB.conf[:MEASURE] = true
          added = IRB.set_measure_callback(type)
          puts "#{added.first} is added."
        else
          IRB.conf[:MEASURE] = true
          added = IRB.set_measure_callback(type)
          puts "#{added.first} is added."
        end
        nil
      end
    end
  end
end
# :startdoc:
