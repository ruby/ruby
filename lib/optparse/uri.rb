# -*- ruby -*-

require 'optparse'
unless defined?(URI)
  begin
    require 'URI/uri'		# Akira Yamada version.
  rescue LoadError
    require 'uri/uri'		# Tomoyuki Kosimizu version.
  end
end
if URI.respond_to?(:parse)
  OptionParser.accept(URI) {|s| [URI.parse(s)] if s}
else
  OptionParser.accept(URI) {|s| [URI.create(s)] if s}
end
