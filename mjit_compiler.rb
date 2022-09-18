# frozen_string_literal: true
# TODO: Merge this to mjit.rb
if RubyVM::MJIT.enabled?
  begin
    require 'etc'
    require 'fiddle'
  rescue LoadError
    return # skip miniruby
  end

  if Fiddle::SIZEOF_VOIDP == 8
    require 'mjit/c_64'
  else
    require 'mjit/c_32'
  end

  require "mjit/instruction"
  require "mjit/compiler"
end
