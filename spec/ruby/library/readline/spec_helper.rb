require_relative '../../spec_helper'

begin
  require 'readline'
rescue LoadError
else
  # rb-readline behaves quite differently
  unless defined?(RbReadline)
    MSpec.enable_feature :readline
  end
end
