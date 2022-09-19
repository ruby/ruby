# frozen_string_literal: true
# TODO: Merge this to mjit.rb
if RubyVM::MJIT.enabled?
  begin
    require 'fiddle'
    require 'fiddle/import'
  rescue LoadError
    return # skip miniruby
  end

  require "mjit/c_type"
  require "mjit/instruction"
  require "mjit/compiler"
end
