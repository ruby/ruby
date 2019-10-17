# frozen_string_literal: true
require 'optparse'

class OptionParser
  def define_by_keywords(options, meth, **opts)
    meth.parameters.each do |type, name|
      case type
      when :key, :keyreq
        op, cl = *(type == :key ? %w"[ ]" : ["", ""])
        define("--#{name}=#{op}#{name.upcase}#{cl}", *opts[name]) do |o|
          options[name] = o
        end
      end
    end
    options
  end
end
