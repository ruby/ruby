require File.expand_path('../../../spec_helper', __FILE__)

unless MSpec.retrieve(:features).key?(:readline)
  begin
    require 'readline'
  rescue LoadError
  else
    # rb-readline behaves quite differently
    if $".grep(/\brbreadline\.rb$/).empty?
      MSpec.enable_feature :readline
    end
  end
end
