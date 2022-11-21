# frozen_string_literal: false

# This class is the base class for \Net::HTTP request classes;
# it wraps together the request path and the request headers.
#
# The class should not be used directly;
# instead you should use its subclasses:
#
# - \Net::HTTP::Get
# - \Net::HTTP::Head
# - \Net::HTTP::Post
# - \Net::HTTP::Delete
# - \Net::HTTP::Options
# - \Net::HTTP::Trace
# - \Net::HTTP::Patch
# - \Net::HTTP::Put
# - \Net::HTTP::Copy
# - \Net::HTTP::Lock
# - \Net::HTTP::Mkcol
# - \Net::HTTP::Move
# - \Net::HTTP::Propfind
# - \Net::HTTP::Proppatch
# - \Net::HTTP::Unlock
#
class Net::HTTPRequest < Net::HTTPGenericRequest
  # Creates an HTTP request object for +path+.
  #
  # +initheader+ are the default headers to use.  Net::HTTP adds
  # Accept-Encoding to enable compression of the response body unless
  # Accept-Encoding or Range are supplied in +initheader+.

  def initialize(path, initheader = nil)
    super self.class::METHOD,
          self.class::REQUEST_HAS_BODY,
          self.class::RESPONSE_HAS_BODY,
          path, initheader
  end
end

