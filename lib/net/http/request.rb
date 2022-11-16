# frozen_string_literal: false

# This class is the base class for \Net::HTTP request classes;
# it wraps together the request path and the request headers.
#
# The class should not be used directly;
# instead you should use its subclasses, which are covered in the sections below.
#
# == About the Examples
#
# Examples here assume that <tt>net/http</tt> has been required
# (which also requires +uri+):
#
#   require 'net/http'
#
# Many code examples here use these example websites:
#
# - https://jsonplaceholder.typicode.com.
# - http://example.com.
#
# Some examples also assume these variables:
#
#   uri = URI('https://jsonplaceholder.typicode.com')
#   uri.freeze # Examples may not modify.
#   hostname = uri.hostname # => "jsonplaceholder.typicode.com"
#   port = uri.port         # => 443
#
# An example that needs a modified URI first duplicates +uri+, then modifies:
#
#   _uri = uri.dup
#   _uri.path = '/todos/1'
#
# == Requests
#
# === \Net::HTTP::Get
#
# A GET request may be sent using request class \Net::HTTP::Get:
#
#   req = Net::HTTP::Get.new(uri) # => #<Net::HTTP::Get GET>
#   Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end # => #<Net::HTTPOK 200 OK readbody=true>
#
# === \Net::HTTP::Head
#
# A HEAD request may be sent using request class \Net::HTTP::Head:
#
#   req = Net::HTTP::Head.new(uri) # => #<Net::HTTP::Head HEAD>
#   Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end # => #<Net::HTTPOK 200 OK readbody=true>
#
# === \Net::HTTP::Post
#
# A POST request may be sent using request class \Net::HTTP::Post:
#
#   _uri = uri.dup
#   _uri.path = '/posts'
#   req = Net::HTTP::Post.new(_uri) # => #<Net::HTTP::Post POST>
#   req.body = '{"title": "foo", "body": "bar", "userId": 1}'
#   req['Content-type'] = 'application/json; charset=UTF-8'
#   Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end # => # => #<Net::HTTPCreated 201 Created readbody=true>
#
# === \Net::HTTP::Patch
# === \Net::HTTP::Put
# === \Net::HTTP::Proppatch
# === \Net::HTTP::Lock
# === \Net::HTTP::Unlock
# === \Net::HTTP::Options
# === \Net::HTTP::Propfind
# === \Net::HTTP::Delete
# === \Net::HTTP::Move
# === \Net::HTTP::Copy
# === \Net::HTTP::Mkcol
# === \Net::HTTP::Trace
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

