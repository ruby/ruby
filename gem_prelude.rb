begin
  require 'rubygems'
rescue LoadError => e
  raise unless e.path == 'rubygems'

  warn "`RubyGems' were not loaded."
else
  require 'bundled_gems'
end if defined?(Gem)

if defined?(ErrorHighlight) || defined?(DidYouMean) || defined?(SyntaxSuggest)
  # Replace empty modules with autoload entries for lazy loading.
  # Direct constant access (e.g. DidYouMean::SpellChecker) triggers
  # autoload transparently; error display uses the hook below.
  if defined?(ErrorHighlight)
    Object.send(:remove_const, :ErrorHighlight)
    autoload :ErrorHighlight, 'error_highlight'
  end
  if defined?(DidYouMean)
    Object.send(:remove_const, :DidYouMean)
    autoload :DidYouMean, 'did_you_mean'
  end
  if defined?(SyntaxSuggest)
    Object.send(:remove_const, :SyntaxSuggest)
    autoload :SyntaxSuggest, 'syntax_suggest'
  end

  module Exception::DetailedMessage # :nodoc:
    @require = Kernel.instance_method(:require)

    def detailed_message(...)
      gem_above = self.class.instance_method(:detailed_message).owner != Exception::DetailedMessage

      # Temporarily restore the original require to bypass any user
      # monkeypatching during gem loading (including nested requires).
      orig = Exception::DetailedMessage.instance_variable_get(:@require)
      patched = Kernel.instance_method(:require)
      Kernel.define_method(:require, orig)
      begin
        require 'error_highlight' rescue LoadError
        require 'did_you_mean' rescue LoadError
        require 'syntax_suggest' rescue LoadError
      ensure
        Kernel.define_method(:require, patched)
      end

      Exception::DetailedMessage.remove_method(:detailed_message)
      gem_above ? super : detailed_message(...)
    end
  end
  Exception.prepend(Exception::DetailedMessage)
end
