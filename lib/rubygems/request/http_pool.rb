##
# A connection "pool" that only manages one connection for now.  Provides
# thread safe `checkout` and `checkin` methods.  The pool consists of one
# connection that corresponds to `http_args`.  This class is private, do not
# use it.

class Gem::Request::HTTPPool # :nodoc:
  attr_reader :cert_files, :proxy_uri

  def initialize http_args, cert_files, proxy_uri
    @http_args  = http_args
    @cert_files = cert_files
    @proxy_uri  = proxy_uri
    @queue      = SizedQueue.new 1
    @queue << nil
  end

  def checkout
    @queue.pop || make_connection
  end

  def checkin connection
    @queue.push connection
  end

  private

  def make_connection
    setup_connection Gem::Request::ConnectionPools.client.new(*@http_args)
  end

  def setup_connection connection
    connection.start
    connection
  end

end

