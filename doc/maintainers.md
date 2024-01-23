# Maintainers
This page describes the current branch, module, library, and extension maintainers of Ruby.

## Branch Maintainers

A branch maintainer is responsible for backporting commits into stable branches
and publishing Ruby patch releases.

[The list of current branch maintainers is available in the wiki](https://github.com/ruby/ruby/wiki/Release-Engineering).

## Module Maintainers
A module maintainer is responsible for a certain part of Ruby.

* The maintainer fixes bugs of the part. Particularly, they should fix
  security vulnerabilities as soon as possible.
* They handle issues related the module on the Redmine or ML.
* They may be discharged by the 3 months rule [[ruby-core:25764]](https://blade.ruby-lang.org/ruby-core/25764).
* They have commit right to Ruby's repository to modify their part in the
  repository.
* They have "developer" role on the Redmine to modify issues.
* They have authority to decide the feature of their part. But they should
  always respect discussions on ruby-core/ruby-dev.

A submaintainer of a module is like a maintainer. But the submaintainer does
not have authority to change/add a feature on his/her part. They need
consensus on ruby-core/ruby-dev before changing/adding. Some of submaintainers
have commit right, others don't.

### Language core features including security
* Yukihiro Matsumoto (matz)

### Evaluator
* Koichi Sasada (ko1)

### Core classes
* Yukihiro Matsumoto (matz)

## Standard Library Maintainers
### Libraries
#### lib/mkmf.rb
* *unmaintained*

#### lib/rubygems.rb, lib/rubygems/*
* Eric Hodel (drbrain)
* Hiroshi SHIBATA (hsbt)
* https://github.com/rubygems/rubygems

#### lib/unicode_normalize.rb, lib/unicode_normalize/*
* Martin J. Dürst

### Extensions
#### ext/continuation
* Koichi Sasada (ko1)

#### ext/coverage
* Yusuke Endoh (mame)

#### ext/fiber
* Koichi Sasada (ko1)

#### ext/monitor
* Koichi Sasada (ko1)

#### ext/objspace
* *unmaintained*

#### ext/pty
* *unmaintained*

#### ext/ripper
* *unmaintained*

#### ext/socket
* Tanaka Akira (akr)
* API change needs matz's approval

#### ext/win32
* NAKAMURA Usaku (usa)

## Default gems Maintainers
### Libraries

#### lib/benchmark.rb
* *unmaintained*
* https://github.com/ruby/benchmark
* https://rubygems.org/gems/benchmark

#### lib/bundler.rb, lib/bundler/*
* Hiroshi SHIBATA (hsbt)
* https://github.com/rubygems/rubygems
* https://rubygems.org/gems/bundler

#### lib/cgi.rb, lib/cgi/*
* *unmaintained*
* https://github.com/ruby/cgi
* https://rubygems.org/gems/cgi

#### lib/English.rb
* *unmaintained*
* https://github.com/ruby/English
* https://rubygems.org/gems/English

#### lib/delegate.rb
* *unmaintained*
* https://github.com/ruby/delegate
* https://rubygems.org/gems/delegate

#### lib/did_you_mean.rb
* Yuki Nishijima (yuki24)
* https://github.com/ruby/did_you_mean
* https://rubygems.org/gems/did_you_mean

#### ext/digest, ext/digest/*
* Akinori MUSHA (knu)
* https://github.com/ruby/digest
* https://rubygems.org/gems/digest

#### lib/erb.rb
* Masatoshi SEKI (seki)
* Takashi Kokubun (k0kubun)
* https://github.com/ruby/erb
* https://rubygems.org/gems/erb

#### lib/error_highlight.rb, lib/error_highlight/*
* Yusuke Endoh (mame)
* https://github.com/ruby/error_highlight
* https://rubygems.org/gems/error_highlight

#### lib/fileutils.rb
* *unmaintained*
* https://github.com/ruby/fileutils
* https://rubygems.org/gems/fileutils

#### lib/find.rb
* Kazuki Tsujimoto (ktsj)
* https://github.com/ruby/find
* https://rubygems.org/gems/find

#### lib/forwardable.rb
* Keiju ISHITSUKA (keiju)
* https://github.com/ruby/forwardable
* https://rubygems.org/gems/forwardable

#### lib/ipaddr.rb
* Akinori MUSHA (knu)
* https://github.com/ruby/ipaddr
* https://rubygems.org/gems/ipaddr

#### lib/irb.rb, lib/irb/*
* Stan Lo (st0012)
* Tomoya Ishida (tompng)
* Mari Imaizumi (ima1zumi)
* Hitoshi Hasumi (hasumikin)
* https://github.com/ruby/irb
* https://rubygems.org/gems/irb

#### lib/optparse.rb, lib/optparse/*
* Nobuyuki Nakada (nobu)
* https://github.com/ruby/optparse

#### lib/logger.rb
* Naotoshi Seo (sonots)
* https://github.com/ruby/logger
* https://rubygems.org/gems/logger

#### lib/net/http.rb, lib/net/https.rb
* NARUSE, Yui (naruse)
* https://github.com/ruby/net-http
* https://rubygems.org/gems/net-http

#### lib/net/protocol.rb
* *unmaintained*
* https://github.com/ruby/net-protocol
* https://rubygems.org/gems/net-protocol

#### lib/open3.rb
* *unmaintained*
* https://github.com/ruby/open3
* https://rubygems.org/gems/open3

#### lib/open-uri.rb
* Tanaka Akira (akr)
* https://github.com/ruby/open-uri

#### lib/ostruct.rb
* Marc-André Lafortune (marcandre)
* https://github.com/ruby/ostruct
* https://rubygems.org/gems/ostruct

#### lib/pp.rb
* Tanaka Akira (akr)
* https://github.com/ruby/pp
* https://rubygems.org/gems/pp

#### lib/prettyprint.rb
* Tanaka Akira (akr)
* https://github.com/ruby/prettyprint
* https://rubygems.org/gems/prettyprint

#### lib/prism.rb
* Kevin Newton (kddnewton)
* Jemma Issroff (jemmaissroff)
* https://github.com/ruby/prism
* https://rubygems.org/gems/prism

#### lib/pstore.rb
* *unmaintained*
* https://github.com/ruby/pstore
* https://rubygems.org/gems/pstore

#### lib/readline.rb
* aycabta
* https://github.com/ruby/readline
* https://rubygems.org/gems/readline

#### lib/resolv.rb
* Tanaka Akira (akr)
* https://github.com/ruby/resolv
* https://rubygems.org/gems/resolv

#### lib/rdoc.rb, lib/rdoc/*
* Eric Hodel (drbrain)
* Hiroshi SHIBATA (hsbt)
* https://github.com/ruby/rdoc
* https://rubygems.org/gems/rdoc

#### lib/reline.rb, lib/reline/*
* Tomoya Ishida (tompng)
* Mari Imaizumi (ima1zumi)
* Stan Lo (st0012)
* Hitoshi Hasumi (hasumikin)
* https://github.com/ruby/reline
* https://rubygems.org/gems/reline

#### lib/securerandom.rb
* Tanaka Akira (akr)
* https://github.com/ruby/securerandom
* https://rubygems.org/gems/securerandom

#### lib/set.rb
* Akinori MUSHA (knu)
* https://github.com/ruby/set
* https://rubygems.org/gems/set

#### lib/shellwords.rb
* Akinori MUSHA (knu)
* https://github.com/ruby/shellwords
* https://rubygems.org/gems/shellwords

#### lib/singleton.rb
* Yukihiro Matsumoto (matz)
* https://github.com/ruby/singleton
* https://rubygems.org/gems/singleton

#### lib/tempfile.rb
* *unmaintained*
* https://github.com/ruby/tempfile
* https://rubygems.org/gems/tempfile

#### lib/time.rb
* Tanaka Akira (akr)
* https://github.com/ruby/time
* https://rubygems.org/gems/time

#### lib/timeout.rb
* Yukihiro Matsumoto (matz)
* https://github.com/ruby/timeout
* https://rubygems.org/gems/timeout

#### lib/thwait.rb
* Keiju ISHITSUKA (keiju)
* https://github.com/ruby/thwait
* https://rubygems.org/gems/thwait

#### lib/tmpdir.rb
* *unmaintained*
* https://github.com/ruby/tmpdir
* https://rubygems.org/gems/tmpdir

#### lib/tsort.rb
* Tanaka Akira (akr)
* https://github.com/ruby/tsort
* https://rubygems.org/gems/tsort

#### lib/un.rb
* WATANABE Hirofumi (eban)
* https://github.com/ruby/un
* https://rubygems.org/gems/un

#### lib/uri.rb, lib/uri/*
* NARUSE, Yui (naruse)
* https://github.com/ruby/uri
* https://rubygems.org/gems/uri

#### lib/yaml.rb, lib/yaml/*
* Aaron Patterson (tenderlove)
* Hiroshi SHIBATA (hsbt)
* https://github.com/ruby/yaml
* https://rubygems.org/gems/yaml

#### lib/weakref.rb
* *unmaintained*
* https://github.com/ruby/weakref
* https://rubygems.org/gems/weakref

### Extensions

#### ext/cgi
* Nobuyoshi Nakada (nobu)
* https://github.com/ruby/cgi
* https://rubygems.org/gems/cgi

#### ext/date
* *unmaintained*
* https://github.com/ruby/date
* https://rubygems.org/gems/date

#### ext/etc
* *unmaintained*
* https://github.com/ruby/etc
* https://rubygems.org/gems/etc

#### ext/fcntl
* *unmaintained*
* https://github.com/ruby/fcntl
* https://rubygems.org/gems/fcntl

#### ext/fiddle
* Aaron Patterson (tenderlove)
* https://github.com/ruby/fiddle
* https://rubygems.org/gems/fiddle

#### ext/io/console
* Nobuyuki Nakada (nobu)
* https://github.com/ruby/io-console
* https://rubygems.org/gems/io-console

#### ext/io/nonblock
* Nobuyuki Nakada (nobu)
* https://github.com/ruby/io-nonblock
* https://rubygems.org/gems/io-nonblock

#### ext/io/wait
* Nobuyuki Nakada (nobu)
* https://github.com/ruby/io-wait
* https://rubygems.org/gems/io-wait

#### ext/json
* NARUSE, Yui (naruse)
* Hiroshi SHIBATA (hsbt)
* https://github.com/flori/json
* https://rubygems.org/gems/json

#### ext/openssl
* Kazuki Yamaguchi (rhe)
* https://github.com/ruby/openssl
* https://rubygems.org/gems/openssl

#### ext/pathname
* Tanaka Akira (akr)
* https://github.com/ruby/pathname
* https://rubygems.org/gems/pathname

#### ext/psych
* Aaron Patterson (tenderlove)
* Hiroshi SHIBATA (hsbt)
* https://github.com/ruby/psych
* https://rubygems.org/gems/psych

#### ext/stringio
* Nobuyuki Nakada (nobu)
* https://github.com/ruby/stringio
* https://rubygems.org/gems/stringio

#### ext/strscan
* Kouhei Sutou (kou)
* https://github.com/ruby/strscan
* https://rubygems.org/gems/strscan

#### ext/win32ole
* Masaki Suketa (suke)
* https://github.com/ruby/win32ole
* https://rubygems.org/gems/win32ole

#### ext/zlib
* NARUSE, Yui (naruse)
* https://github.com/ruby/zlib
* https://rubygems.org/gems/zlib

## Bundled gems upstream repositories
### minitest
* https://github.com/minitest/minitest

### power_assert
* https://github.com/ruby/power_assert

### rake
* https://github.com/ruby/rake

### test-unit
* https://github.com/test-unit/test-unit

### rexml
* https://github.com/ruby/rexml

### rss
* https://github.com/ruby/rss

### net-ftp
* https://github.com/ruby/net-ftp

### net-imap
* https://github.com/ruby/net-imap

### net-pop
* https://github.com/ruby/net-pop

### net-smtp
* https://github.com/ruby/net-smtp

### matrix
* https://github.com/ruby/matrix

### prime
* https://github.com/ruby/prime

### rbs
* https://github.com/ruby/rbs

### typeprof
* https://github.com/ruby/typeprof

### debug
* https://github.com/ruby/debug

### racc
* https://github.com/ruby/racc

#### mutex_m
* https://github.com/ruby/mutex_m

#### getoptlong
* https://github.com/ruby/getoptlong

#### base64
* https://github.com/ruby/base64

#### bigdecimal
* https://github.com/ruby/bigdecimal

#### observer
* https://github.com/ruby/observer

#### abbrev
* https://github.com/ruby/abbrev

#### resolv-replace
* https://github.com/ruby/resolv-replace

#### rinda
* https://github.com/ruby/rinda

#### drb
* https://github.com/ruby/drb

#### nkf
* https://github.com/ruby/nkf

#### syslog
* https://github.com/ruby/syslog

#### csv
* https://github.com/ruby/csv

## Platform Maintainers
### mswin64 (Microsoft Windows)
* NAKAMURA Usaku (usa)

### mingw32 (Minimalist GNU for Windows)
* Nobuyoshi Nakada (nobu)

### AIX
* Yutaka Kanemoto (kanemoto)

### FreeBSD
* Akinori MUSHA (knu)

### Solaris
* Naohisa Goto (ngoto)

### RHEL, CentOS
* KOSAKI Motohiro (kosaki)

### macOS
* Kenta Murata (mrkn)

### OpenBSD
* Jeremy Evans (jeremyevans0)

### cygwin, ...
* none. (Maintainer WANTED)

### WebAssembly/WASI
* Yuta Saito (katei)
