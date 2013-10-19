require 'cgi'
require 'uri'

class Gem::UriFormatter
  attr_reader :uri

  def initialize uri
    @uri = uri
  end

  def escape
    return unless @uri
    CGI.escape @uri
  end

  ##
  # Normalize the URI by adding "http://" if it is missing.

  def normalize
    (@uri =~ /^(https?|ftp|file):/i) ? @uri : "http://#{@uri}"
  end

  def unescape
    return unless @uri
    CGI.unescape @uri
  end

end

