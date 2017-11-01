# frozen_string_literal: true

require "logger"
module Spec
  class SilentLogger
    (::Logger.instance_methods - Object.instance_methods).each do |logger_instance_method|
      define_method(logger_instance_method) {|*args, &blk| }
    end
  end
end
