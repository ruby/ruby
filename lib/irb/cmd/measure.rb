require_relative "nop"

# :stopdoc:
module IRB
  module ExtendCommand
    class Measure < Nop
      def initialize(*args)
        super(*args)
      end

      def execute(type = nil, arg = nil, &block)
        case type
        when :off
          IRB.conf[:MEASURE] = nil
          IRB.unset_measure_callback(arg)
        when :list
          IRB.conf[:MEASURE_CALLBACKS].each do |type_name, _, arg_val|
            puts "- #{type_name}" + (arg_val ? "(#{arg_val.inspect})" : '')
          end
        when :on
          IRB.conf[:MEASURE] = true
          added = IRB.set_measure_callback(type, arg)
          puts "#{added[0]} is added." if added
        else
          if block_given?
            IRB.conf[:MEASURE] = true
            added = IRB.set_measure_callback(&block)
            puts "#{added[0]} is added." if added
          else
            IRB.conf[:MEASURE] = true
            added = IRB.set_measure_callback(type, arg)
            puts "#{added[0]} is added." if added
          end
        end
        nil
      end
    end
  end
end
# :startdoc:
