require 'uri'

class Gem::UriFormatter
  attr_reader :uri

  def initialize uri
    @uri = uri
  end

  def escape
    return unless @uri
    escaper.escape @uri
  end

  ##
  # Normalize the URI by adding "http://" if it is missing.

  def normalize
    (@uri =~ /^(https?|ftp|file):/i) ? @uri : "http://#{@uri}"
  end

  def unescape
    return unless @uri
    escaper.unescape @uri
  end

  private

  def escaper
    @uri_parser ||=
      begin
        URI::Parser.new
      rescue NameError
        URI
      end
  end

end

