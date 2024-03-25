# frozen_string_literal: true
require_relative '../optparse'

class OptionParser
  # :call-seq:
  #   define_by_keywords(options, method, **params)
  #
  # :include: ../../doc/optparse/creates_option.rdoc
  #
  # Defines options which set in to _options_ for keyword parameters
  # of _method_.
  #
  # Parameters for each keywords are given as elements of _params_.
  #
  def define_by_keywords(options, method, **params)
    method.parameters.each do |type, name|
      case type
      when :key, :keyreq
        op, cl = *(type == :key ? %w"[ ]" : ["", ""])
        define("--#{name}=#{op}#{name.upcase}#{cl}", *params[name]) do |o|
          options[name] = o
        end
      end
    end
    options
  end
end
