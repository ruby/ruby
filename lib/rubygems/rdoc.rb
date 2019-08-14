# frozen_string_literal: true
require 'rubygems'

begin
  gem 'rdoc'
rescue Gem::LoadError
  # swallow
else
  # This will force any deps that 'rdoc' might have
  # (such as json) that are ambiguous to be activated, which
  # is important because we end up using Specification.reset
  # and we don't want the warning it pops out.
  Gem.finish_resolve
end

begin
  require 'rdoc/rubygems_hook'
  module Gem
    RDoc = ::RDoc::RubygemsHook
  end

  Gem.done_installing(&Gem::RDoc.method(:generation_hook))
rescue LoadError
end
