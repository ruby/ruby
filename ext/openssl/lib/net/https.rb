=begin
= $RCSfile$ -- SSL/TLS enhancement for Net::HTTP.

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU Yuuzou <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Requirements
  This program requires Net 1.2.0 or higher version.
  You can get it from RAA or Ruby's CVS repository.

= Version
  $Id$
  
  2001/11/06: Contiributed to Ruby/OpenSSL project.

== class Net::HTTP

== Example

Simple HTTP client is here:

    require 'net/http'
    host, port, path = "localhost", 80, "/"
    if %r!http://(.*?)(?::(\d+))?(/.*)! =~ ARGV[0]
      host   = $1
      port   = $2.to_i if $2
      path   = $3
    end
    h = Net::HTTP.new(host, port)
    h.request_get(path) {|res| print res.body }

It can be replaced by follow one:

    require 'net/https'
    host, port, path = "localhost", 80, "/"
    if %r!(https?)://(.*?)(?::(\d+))?(/.*)! =~ ARGV[0]
      scheme = $1
      host   = $2
      port   = $3 ? $3.to_i : ((scheme == "http") ? 80 : 443)
      path   = $4
    end
    h = Net::HTTP.new(host, port)
    h.use_ssl = true if scheme == "https" # enable SSL/TLS
    h.request_get(path) {|res| print res.body }

=== Instance Methods

: use_ssl
    returns ture if use SSL/TLS with HTTP.

: use_ssl=((|true_or_false|))
    sets use_ssl.

: peer_cert
    return the X.509 certificates the server presented.

: key=((|key|))
    Sets an OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
    (This method is appeared in Michal Rokos's OpenSSL extention.)

: key_file=((|path|))
    Sets a private key file to use in PEM format.

: cert=((|cert|))
    Sets an OpenSSL::X509::Certificate object as client certificate.
    (This method is appeared in Michal Rokos's OpenSSL extention.)

: cert_file=((|path|))
    Sets pathname of a X.509 certification file in PEM format.

: ca_file=((|path|))
    Sets path of a CA certification file in PEM format.
    The file can contrain several CA certificats.

: ca_path=((|path|))
    Sets path of a CA certification directory containing certifications
    in PEM format.

: verify_mode=((|mode|))
    Sets the flags for server the certification verification at
    begining of SSL/TLS session.
    OpenSSL::SSL::VERIFY_NONE or OpenSSL::SSL::VERIFY_PEER is acceptable.

: verify_callback=((|proc|))
    Sets the verify callback for the server certification verification.

: verify_depth=((|num|))
    Sets the maximum depth for the certificate chain verification.

: cert_store=((|store|))
    Sets the X509::Store to verify peer certificate.

=end

# HTTPS implementation is merged in to net/http.
require 'net/http'
