# frozen_string_literal: true

require "rubygems/uri_parser"

module Gem::UriParsing

  def parse_uri(source_uri)
    return source_uri unless source_uri.is_a?(String)

    uri_parser.parse(source_uri)
  end

  private :parse_uri

  def uri_parser
    require "uri"

    Gem::UriParser.new
  end

  private :uri_parser

end
