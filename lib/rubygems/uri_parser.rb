# frozen_string_literal: true

##
# The UriParser handles parsing URIs.
#

class Gem::UriParser
  ##
  # Parses the #uri, raising if it's invalid

  def parse!(uri)
    raise URI::InvalidURIError unless uri

    # Always escape URI's to deal with potential spaces and such
    # It should also be considered that source_uri may already be
    # a valid URI with escaped characters. e.g. "{DESede}" is encoded
    # as "%7BDESede%7D". If this is escaped again the percentage
    # symbols will be escaped.
    begin
      URI.parse(uri)
    rescue URI::InvalidURIError
      URI.parse(URI::DEFAULT_PARSER.escape(uri))
    end
  end

  ##
  # Parses the #uri, returning the original uri if it's invalid

  def parse(uri)
    parse!(uri)
  rescue URI::InvalidURIError
    uri
  end
end
