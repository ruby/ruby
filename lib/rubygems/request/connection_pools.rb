# frozen_string_literal: false
require 'thread'

class Gem::Request::ConnectionPools # :nodoc:

  @client = Net::HTTP

  class << self
    attr_accessor :client
  end

  def initialize proxy_uri, cert_files
    @proxy_uri  = proxy_uri
    @cert_files = cert_files
    @pools      = {}
    @pool_mutex = Mutex.new
  end

  def pool_for uri
    http_args = net_http_args(uri, @proxy_uri)
    key       = http_args + [https?(uri)]
    @pool_mutex.synchronize do
      @pools[key] ||=
        if https? uri then
          Gem::Request::HTTPSPool.new(http_args, @cert_files, @proxy_uri)
        else
          Gem::Request::HTTPPool.new(http_args, @cert_files, @proxy_uri)
        end
    end
  end

  def close_all
    @pools.each_value {|pool| pool.close_all}
  end

  private

  ##
  # Returns list of no_proxy entries (if any) from the environment

  def get_no_proxy_from_env
    env_no_proxy = ENV['no_proxy'] || ENV['NO_PROXY']

    return [] if env_no_proxy.nil?  or env_no_proxy.empty?

    env_no_proxy.split(/\s*,\s*/)
  end

  def https? uri
    uri.scheme.downcase == 'https'
  end

  def no_proxy? host, env_no_proxy
    host = host.downcase

    env_no_proxy.any? do |pattern|
      pattern = pattern.downcase

      host[-pattern.length, pattern.length] == pattern or
        (pattern.start_with? '.' and pattern[1..-1] == host)
    end
  end

  def net_http_args uri, proxy_uri
    # URI::Generic#hostname was added in ruby 1.9.3, use it if exists, otherwise
    # don't support IPv6 literals and use host.
    hostname = uri.respond_to?(:hostname) ? uri.hostname : uri.host
    net_http_args = [hostname, uri.port]

    no_proxy = get_no_proxy_from_env

    if proxy_uri and not no_proxy?(hostname, no_proxy) then
      proxy_hostname = proxy_uri.respond_to?(:hostname) ? proxy_uri.hostname : proxy_uri.host
      net_http_args + [
        proxy_hostname,
        proxy_uri.port,
        Gem::UriFormatter.new(proxy_uri.user).unescape,
        Gem::UriFormatter.new(proxy_uri.password).unescape,
      ]
    elsif no_proxy? hostname, no_proxy then
      net_http_args + [nil, nil]
    else
      net_http_args
    end
  end

end

