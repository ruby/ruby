# frozen_string_literal: true

# If this file is exist, RDoc generates and removes documents by rubygems plugins.
#
# In follwing cases,
# RubyGems directly exectute RDoc::RubygemsHook.generation_hook and RDoc::RubygemsHook#remove to generate and remove documents.
#
# - RDoc is used as a default gem.
# - RDoc is a old version that doesn't have rubygems_plugin.rb.

require_relative 'rdoc/rubygems_hook'

# To install dependency libraries of RDoc, you need to run bundle install.
# At that time, rdoc/markdown is not generated.
# If generate and remove are executed at that time, an error will occur.
# So, we can't register generate and remove to Gem at that time.
begin
  require_relative 'rdoc/markdown'
rescue LoadError
else
  Gem.done_installing(&RDoc::RubyGemsHook.method(:generate))
  Gem.pre_uninstall(&RDoc::RubyGemsHook.method(:remove))
end
