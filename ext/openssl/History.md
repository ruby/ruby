Version 2.2.0 (not yet released)
=============

* Change default `OpenSSL::SSL::SSLServer#listen` backlog argument from
  5 to `Socket::SOMAXCONN`.
* Make `OpenSSL::HMAC#==` use a timing safe string comparison.
* Remove unsupported MDC2, DSS, DSS1, and SHA algorithms.
* Add support for SHA3 and BLAKE digests.
* Add `OpenSSL::SSL::SSLSocket.open` for opening a `TCPSocket` and
  returning an `OpenSSL::SSL::SSLSocket` for it.
* Support marshalling of `OpenSSL::X509` objects.
* Add `OpenSSL.secure_compare` for timing safe string comparison for
  strings of possibly unequal length.
* Add `OpenSSL.fixed_length_secure_compare` for timing safe string
  comparison for strings of equal length.
* Add `OpenSSL::SSL::SSLSocket#{finished_message,peer_finished_message}`
  for last finished message sent and received.
* Add `OpenSSL::Timestamp` module for handing timestamp requests and
  responses.
* Add helper methods for `OpenSSL::X509::Certificate`:
  `find_extension`, `subject_key_identifier`,
  `authority_key_identifier`, `crl_uris`, `ca_issuer_uris` and
  `ocsp_uris`.
* Add helper methods for `OpenSSL::X509::CRL`:
  `find_extension` and `subject_key_identifier`.
* Remove `OpenSSL::PKCS7::SignerInfo#name` alias for `#issuer`.
* Add `OpenSSL::ECPoint#add` for adding points to an elliptic curve
  group.
  [[GitHub #261]](https://github.com/ruby/openssl/pull/261)
* Make `OpenSSL::PKey::RSA#{export,to_der}` correctly check `key`,
  `factors`, and `crt_params`.
  [[GitHub #258]](https://github.com/ruby/openssl/pull/258)
* Add `OpenSSL::SSL::{SSLSocket,SSLServer}#fileno`, returning the
  underlying socket file descriptor number.
  [[GitHub #247]](https://github.com/ruby/openssl/pull/247)
* Support client certificates with TLS 1.3, and support post-handshake
  authentication with OpenSSL 1.1.1+.
  [[GitHub #239]](https://github.com/ruby/openssl/pull/239)
* Add `OpenSSL::ASN1::ObjectId#==` for equality testing.
* Add `OpenSSL::X509::Extension#value_der` for the raw value of
  the extension.
  [[GitHub #234]](https://github.com/ruby/openssl/pull/234)
* Signficantly reduce allocated memory in `OpenSSL::Buffering#do_write`.
  [[GitHub #212]](https://github.com/ruby/openssl/pull/212)
* Ensure all valid IPv6 addresses are considered valid as elements
  of subjectAlternativeName in certificates.
  [[GitHub #185]](https://github.com/ruby/openssl/pull/185)
* Allow recipient's certificate to be omitted in PCKS7#decrypt.
  [[GitHub #183]](https://github.com/ruby/openssl/pull/183)
* Add support for reading keys in PKCS8 format and export via instance methods
  added to `OpenSSL::PKey` classes: `private_to_der`, `private_to_pem`,
  `public_to_der` and `public_to_pem`.

Version 2.1.2
=============

Merged changes in 2.0.9.


Version 2.1.1
=============

Merged changes in 2.0.8.


Version 2.1.0
=============

Notable changes
---------------

* Support for OpenSSL versions before 1.0.1 and LibreSSL versions before 2.5
  is removed.
  [[GitHub #86]](https://github.com/ruby/openssl/pull/86)
* OpenSSL::BN#negative?, #+@, and #-@ are added.
* OpenSSL::SSL::SSLSocket#connect raises a more informative exception when
  certificate verification fails.
  [[GitHub #99]](https://github.com/ruby/openssl/pull/99)
* OpenSSL::KDF module is newly added. In addition to PBKDF2-HMAC that has moved
  from OpenSSL::PKCS5, scrypt and HKDF are supported.
  [[GitHub #109]](https://github.com/ruby/openssl/pull/109)
  [[GitHub #173]](https://github.com/ruby/openssl/pull/173)
* OpenSSL.fips_mode is added. We had the setter, but not the getter.
  [[GitHub #125]](https://github.com/ruby/openssl/pull/125)
* OpenSSL::OCSP::Request#signed? is added.
* OpenSSL::ASN1 handles the indefinite length form better. OpenSSL::ASN1.decode
  no longer wrongly treats the end-of-contents octets as part of the content.
  OpenSSL::ASN1::ASN1Data#infinite_length is renamed to #indefinite_length.
  [[GitHub #98]](https://github.com/ruby/openssl/pull/98)
* OpenSSL::X509::Name#add_entry now accepts two additional keyword arguments
  'loc' and 'set'.
  [[GitHub #94]](https://github.com/ruby/openssl/issues/94)
* OpenSSL::SSL::SSLContext#min_version= and #max_version= are added to replace
  #ssl_version= that was built on top of the deprecated OpenSSL C API. Use of
  that method and the constant OpenSSL::SSL::SSLContext::METHODS is now
  deprecated.
  [[GitHub #142]](https://github.com/ruby/openssl/pull/142)
* OpenSSL::X509::Name#to_utf8 is added.
  [[GitHub #26]](https://github.com/ruby/openssl/issues/26)
  [[GitHub #143]](https://github.com/ruby/openssl/pull/143)
* OpenSSL::X509::{Extension,Attribute,Certificate,CRL,Revoked,Request} can be
  compared with == operator.
  [[GitHub #161]](https://github.com/ruby/openssl/pull/161)
* TLS Fallback Signaling Cipher Suite Value (SCSV) support is added.
  [[GitHub #165]](https://github.com/ruby/openssl/pull/165)
* Build failure with OpenSSL 1.1 built with no-deprecated is fixed.
  [[GitHub #160]](https://github.com/ruby/openssl/pull/160)
* OpenSSL::Buffering#write accepts an arbitrary number of arguments.
  [[Feature #9323]](https://bugs.ruby-lang.org/issues/9323)
  [[GitHub #162]](https://github.com/ruby/openssl/pull/162)
* OpenSSL::PKey::RSA#sign_pss and #verify_pss are added. They perform RSA-PSS
  signature and verification.
  [[GitHub #75]](https://github.com/ruby/openssl/issues/75)
  [[GitHub #76]](https://github.com/ruby/openssl/pull/76)
  [[GitHub #169]](https://github.com/ruby/openssl/pull/169)
* OpenSSL::SSL::SSLContext#add_certificate is added.
  [[GitHub #167]](https://github.com/ruby/openssl/pull/167)
* OpenSSL::PKey::EC::Point#to_octet_string is added.
  OpenSSL::PKey::EC::Point.new can now take String as the second argument.
  [[GitHub #177]](https://github.com/ruby/openssl/pull/177)


Version 2.0.9
=============

Security fixes
--------------

* OpenSSL::X509::Name#<=> could incorrectly return 0 (= equal) for non-equal
  objects. CVE-2018-16395 is assigned for this issue.
  https://hackerone.com/reports/387250

Bug fixes
---------

* Fixed OpenSSL::PKey::*.{new,generate} immediately aborting if the thread is
  interrupted.
  [[Bug #14882]](https://bugs.ruby-lang.org/issues/14882)
  [[GitHub #205]](https://github.com/ruby/openssl/pull/205)
* Fixed OpenSSL::X509::Name#to_s failing with OpenSSL::X509::NameError if
  called against an empty instance.
  [[GitHub #200]](https://github.com/ruby/openssl/issues/200)
  [[GitHub #211]](https://github.com/ruby/openssl/pull/211)


Version 2.0.8
=============

Bug fixes
---------

* OpenSSL::Cipher#pkcs5_keyivgen raises an error when a negative iteration
  count is given.
  [[GitHub #184]](https://github.com/ruby/openssl/pull/184)
* Fixed build with LibreSSL 2.7.
  [[GitHub #192]](https://github.com/ruby/openssl/issues/192)
  [[GitHub #193]](https://github.com/ruby/openssl/pull/193)


Version 2.0.7
=============

Bug fixes
---------

* OpenSSL::Cipher#auth_data= could segfault if called against a non-AEAD cipher.
  [[Bug #14024]](https://bugs.ruby-lang.org/issues/14024)
* OpenSSL::X509::Certificate#public_key= (and similar methods) could segfault
  when an instance of OpenSSL::PKey::PKey with no public key components is
  passed.
  [[Bug #14087]](https://bugs.ruby-lang.org/issues/14087)
  [[GitHub #168]](https://github.com/ruby/openssl/pull/168)


Version 2.0.6
=============

Bug fixes
---------

* The session_remove_cb set to an OpenSSL::SSL::SSLContext is no longer called
  during GC.
* A possible deadlock in OpenSSL::SSL::SSLSocket#sysread is fixed.
  [[GitHub #139]](https://github.com/ruby/openssl/pull/139)
* OpenSSL::BN#hash could return an unnormalized fixnum value on Windows.
  [[Bug #13877]](https://bugs.ruby-lang.org/issues/13877)
* OpenSSL::SSL::SSLSocket#sysread and #sysread_nonblock set the length of the
  destination buffer String to 0 on error.
  [[GitHub #153]](https://github.com/ruby/openssl/pull/153)
* Possible deadlock is fixed. This happened only when built with older versions
  of OpenSSL (before 1.1.0) or LibreSSL.
  [[GitHub #155]](https://github.com/ruby/openssl/pull/155)


Version 2.0.5
=============

Bug fixes
---------

* Reading a PEM/DER-encoded private key or certificate from an IO object did
  not work properly on mswin platforms.
  [[ruby/openssl#128]](https://github.com/ruby/openssl/issues/128)
* Broken length check in the PEM passphrase callback is fixed.
* It failed to compile when OpenSSL is configured without TLS 1.0 support.


Version 2.0.4
=============

Bug fixes
---------

* It now compiles with LibreSSL without renaming on Windows (mswin).
* A workaround for the error queue leak of X509_load_cert_crl_file() that
  causes random errors is added.
  [[Bug #11033]](https://bugs.ruby-lang.org/issues/11033)


Version 2.0.3
=============

Bug fixes
---------

* OpenSSL::ASN1::Constructive#each which was broken by 2.0.0 is fixed.
  [[ruby/openssl#96]](https://github.com/ruby/openssl/pull/96)
* Fixed build with static OpenSSL libraries on Windows.
  [[Bug #13080]](https://bugs.ruby-lang.org/issues/13080)
* OpenSSL::X509::Name#eql? which was broken by 2.0.0 is fixed.


Version 2.0.2
=============

Bug fixes
---------

* Fix build with early 0.9.8 series which did not have SSL_CTX_clear_options().
  [ruby-core:78693]


Version 2.0.1
=============

Bug fixes
---------

* A GC issue around OpenSSL::BN is fixed.
  [[ruby/openssl#87]](https://github.com/ruby/openssl/issues/87)
* OpenSSL::ASN1 now parses BER encoding of GeneralizedTime without seconds.
  [[ruby/openssl#88]](https://github.com/ruby/openssl/pull/88)


Version 2.0.0
=============

This is the first release of openssl gem, formerly a standard library of Ruby,
ext/openssl. This is the successor of the version included in Ruby 2.3.

Compatibility notes
-------------------

* Support for OpenSSL version 0.9.6 and 0.9.7 is completely removed. openssl gem
  still works with OpenSSL 0.9.8, but users are strongly encouraged to upgrade
  to at least 1.0.1, as OpenSSL < 1.0.1 will not receive any security fixes from
  the OpenSSL development team.

Supported platforms
-------------------

* OpenSSL 1.0.0, 1.0.1, 1.0.2, 1.1.0
* OpenSSL < 0.9.8 is no longer supported.
* LibreSSL 2.3, 2.4, 2.5
* Ruby 2.3, 2.4

Notable changes
---------------

* Add support for OpenSSL 1.1.0.
  [[Feature #12324]](https://bugs.ruby-lang.org/issues/12324)
* Add support for LibreSSL

* OpenSSL::Cipher

  - OpenSSL::Cipher#key= and #iv= reject too long inputs. They used to truncate
    silently. [[Bug #12561]](https://bugs.ruby-lang.org/issues/12561)

  - OpenSSL::Cipher#iv_len= is added. It allows changing IV (nonce) length if
    using AEAD ciphers.
    [[Bug #8667]](https://bugs.ruby-lang.org/issues/8667),
    [[Bug #10420]](https://bugs.ruby-lang.org/issues/10420),
    [[GH ruby/ruby#569]](https://github.com/ruby/ruby/pull/569),
    [[GH ruby/openssl#58]](https://github.com/ruby/openssl/pull/58)

  - OpenSSL::Cipher#auth_tag_len= is added. This sets the authentication tag
    length to be generated by an AEAD cipher.

* OpenSSL::OCSP

  - Accessor methods are added to OpenSSL::OCSP::CertificateId.
    [[Feature #7181]](https://bugs.ruby-lang.org/issues/7181)

  - OpenSSL::OCSP::Request and BasicResponse can be signed with non-SHA-1 hash
    algorithm. [[Feature #11552]](https://bugs.ruby-lang.org/issues/11552)

  - OpenSSL::OCSP::CertificateId and BasicResponse can be encoded into DER.

  - A new class OpenSSL::OCSP::SingleResponse is added for convenience.

  - OpenSSL::OCSP::BasicResponse#add_status accepts absolute times. They used to
    accept only relative seconds from the current time.

* OpenSSL::PKey

  - OpenSSL::PKey::EC follows the general PKey interface.
    [[Bug #6567]](https://bugs.ruby-lang.org/issues/6567)

  - OpenSSL::PKey.read raises OpenSSL::PKey::PKeyError instead of ArgumentError
    for consistency with OpenSSL::PKey::{DH,DSA,RSA,EC}#new.
    [[Bug #11774]](https://bugs.ruby-lang.org/issues/11774),
    [[GH ruby/openssl#55]](https://github.com/ruby/openssl/pull/55)

  - OpenSSL::PKey::EC::Group retrieved by OpenSSL::PKey::EC#group is no longer
    linked with the EC key. Modifications to the EC::Group have no effect on the
    key. [[GH ruby/openssl#71]](https://github.com/ruby/openssl/pull/71)

  - OpenSSL::PKey::EC::Point#to_bn allows specifying the point conversion form
    by the optional argument.

* OpenSSL::SSL

  - OpenSSL::SSL::SSLSocket#tmp_key is added. A client can call it after the
    connection is established to retrieve the ephemeral key.
    [[GH ruby/ruby#1318]](https://github.com/ruby/ruby/pull/1318)

  - The automatic ephemeral ECDH curve selection is enabled by default when
    built with OpenSSL >= 1.0.2 or LibreSSL.

  - OpenSSL::SSL::SSLContext#security_level= is added. You can set the "security
    level" of the SSL context. This is effective only when built with OpenSSL
    1.1.0.

  - A new option 'verify_hostname' is added to OpenSSL::SSL::SSLContext. When it
    is enabled, and the SNI hostname is also set, the hostname verification on
    the server certificate is automatically performed. It is now enabled by
    OpenSSL::SSL::SSLContext#set_params.
    [[GH ruby/openssl#60]](https://github.com/ruby/openssl/pull/60)

Removals
--------

* OpenSSL::Engine

  - OpenSSL::Engine.cleanup does nothing when built with OpenSSL 1.1.0.

* OpenSSL::SSL

  - OpenSSL::PKey::DH::DEFAULT_512 is removed. Hence servers no longer use
    512-bit DH group by default. It is considered too weak nowadays.
    [[Bug #11968]](https://bugs.ruby-lang.org/issues/11968),
    [[GH ruby/ruby#1196]](https://github.com/ruby/ruby/pull/1196)

  - RC4 cipher suites are removed from OpenSSL::SSL::SSLContext::DEFAULT_PARAMS.
    RC4 is now considered to be weak.
    [[GH ruby/openssl#50]](https://github.com/ruby/openssl/pull/50)

Deprecations
------------

* OpenSSL::PKey

  - OpenSSL::PKey::RSA#n=, #e=, #d=, #p=, #q=, #dmp1=, #dmq1=, #iqmp=,
    OpenSSL::PKey::DSA#p=, #q=, #g=, #priv_key=, #pub_key=,
    OpenSSL::PKey::DH#p=, #g=, #priv_key= and #pub_key= are deprecated. They are
    disabled when built with OpenSSL 1.1.0, due to its API change. Instead,
    OpenSSL::PKey::RSA#set_key, #set_factors, #set_crt_params,
    OpenSSL::PKey::DSA#set_pqg, #set_key, OpenSSL::PKey::DH#set_pqg and #set_key
    are added.

* OpenSSL::Random

  - OpenSSL::Random.pseudo_bytes is deprecated, and not defined when built with
    OpenSSL 1.1.0. Use OpenSSL::Random.random_bytes instead.

* OpenSSL::SSL

  - OpenSSL::SSL::SSLContext#tmp_ecdh_callback is deprecated, as the underlying
    API SSL_CTX_set_tmp_ecdh_callback() is removed in OpenSSL 1.1.0. It was
    first added in Ruby 2.3.0. To specify the curve to be used in ephemeral
    ECDH, use OpenSSL::SSL::SSLContext#ecdh_curves=. The automatic curve
    selection is also now enabled by default when built with a capable OpenSSL.
