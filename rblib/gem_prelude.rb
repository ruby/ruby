begin
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
else
  require 'bundled_gems'
end if defined?(Gem)

begin
  require 'error_highlight'
rescue LoadError
  warn "`error_highlight' was not loaded."
end if defined?(ErrorHighlight)

begin
  require 'did_you_mean'
rescue LoadError
  warn "`did_you_mean' was not loaded."
end if defined?(DidYouMean)

begin
  require 'syntax_suggest/core_ext'
rescue LoadError
  warn "`syntax_suggest' was not loaded."
end if defined?(SyntaxSuggest)

