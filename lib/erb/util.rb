begin
  # ERB::Util.html_escape
  require 'erb/escape'
rescue LoadError # JRuby can't load .so
end

#--
# ERB::Util
#
# A utility module for conversion routines, often handy in HTML generation.
module ERB::Util
  #
  # A utility method for escaping HTML tag characters in _s_.
  #
  #   require "erb"
  #   include ERB::Util
  #
  #   puts html_escape("is a > 0 & a < 10?")
  #
  # _Generates_
  #
  #   is a &gt; 0 &amp; a &lt; 10?
  #
  unless defined?(ERB::Util.html_escape) # for JRuby
    def html_escape(s)
      CGI.escapeHTML(s.to_s)
    end
    module_function :html_escape
  end
  alias h html_escape
  module_function :h

  #
  # A utility method for encoding the String _s_ as a URL.
  #
  #   require "erb"
  #   include ERB::Util
  #
  #   puts url_encode("Programming Ruby:  The Pragmatic Programmer's Guide")
  #
  # _Generates_
  #
  #   Programming%20Ruby%3A%20%20The%20Pragmatic%20Programmer%27s%20Guide
  #
  def url_encode(s)
    CGI.escapeURIComponent(s.to_s)
  end
  alias u url_encode
  module_function :u
  module_function :url_encode
end
