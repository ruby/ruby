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

No maintainer means that there is no specific maintainer for the part now.
The member of ruby core team can fix issues at anytime. But major changes need
consensus on ruby-core/ruby-dev.

### Language core features including security

* Yukihiro Matsumoto ([matz])

### Evaluator

* Koichi Sasada ([ko1])

### Core classes

* Yukihiro Matsumoto ([matz])

### Standard Library Maintainers

#### lib/mkmf.rb

* *No maintainer*

#### lib/rubygems.rb, lib/rubygems/*

* Hiroshi SHIBATA ([hsbt])
* https://github.com/ruby/rubygems

#### lib/unicode_normalize.rb, lib/unicode_normalize/*

* Martin J. Dürst ([duerst])

### Standard Library(Extensions) Maintainers

#### ext/continuation

* Koichi Sasada ([ko1])

#### ext/coverage

* Yusuke Endoh ([mame])

#### ext/fiber

* Koichi Sasada ([ko1])

#### ext/monitor

* Koichi Sasada ([ko1])

#### ext/objspace

* *No maintainer*

#### ext/pty

* *No maintainer*

#### ext/ripper

* *No maintainer*

#### ext/socket

* Tanaka Akira ([akr])
* API change needs matz's approval

#### ext/win32

* NAKAMURA Usaku ([unak])

### Default gems(Libraries) Maintainers

#### lib/bundler.rb, lib/bundler/*

* Hiroshi SHIBATA ([hsbt])
* https://github.com/ruby/rubygems
* https://rubygems.org/gems/bundler

#### lib/cgi/escape.rb

* *No maintainer*

#### lib/English.rb

* *No maintainer*
* https://github.com/ruby/English
* https://rubygems.org/gems/English

#### lib/delegate.rb

* *No maintainer*
* https://github.com/ruby/delegate
* https://rubygems.org/gems/delegate

#### lib/did_you_mean.rb

* Yuki Nishijima ([yuki24])
* https://github.com/ruby/did_you_mean
* https://rubygems.org/gems/did_you_mean

#### ext/digest, ext/digest/*

* Akinori MUSHA ([knu])
* https://github.com/ruby/digest
* https://rubygems.org/gems/digest

#### lib/erb.rb

* Masatoshi SEKI ([seki])
* Takashi Kokubun ([k0kubun])
* https://github.com/ruby/erb
* https://rubygems.org/gems/erb

#### lib/error_highlight.rb, lib/error_highlight/*

* Yusuke Endoh ([mame])
* https://github.com/ruby/error_highlight
* https://rubygems.org/gems/error_highlight

#### lib/fileutils.rb

* *No maintainer*
* https://github.com/ruby/fileutils
* https://rubygems.org/gems/fileutils

#### lib/find.rb

* Kazuki Tsujimoto ([k-tsj])
* https://github.com/ruby/find
* https://rubygems.org/gems/find

#### lib/forwardable.rb

* Keiju ISHITSUKA ([keiju])
* https://github.com/ruby/forwardable
* https://rubygems.org/gems/forwardable

#### lib/ipaddr.rb

* Akinori MUSHA ([knu])
* https://github.com/ruby/ipaddr
* https://rubygems.org/gems/ipaddr

#### lib/optparse.rb, lib/optparse/*

* Nobuyuki Nakada ([nobu])
* https://github.com/ruby/optparse
* https://rubygems.org/gems/optparse

#### lib/net/http.rb, lib/net/https.rb

* NARUSE, Yui ([nurse])
* https://github.com/ruby/net-http
* https://rubygems.org/gems/net-http

#### lib/net/protocol.rb

* *No maintainer*
* https://github.com/ruby/net-protocol
* https://rubygems.org/gems/net-protocol

#### lib/open3.rb

* *No maintainer*
* https://github.com/ruby/open3
* https://rubygems.org/gems/open3

#### lib/open-uri.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/open-uri
* https://rubygems.org/gems/open-uri

#### lib/pp.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/pp
* https://rubygems.org/gems/pp

#### lib/prettyprint.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/prettyprint
* https://rubygems.org/gems/prettyprint

#### lib/prism.rb

* Kevin Newton ([kddnewton])
* Eileen Uchitelle ([eileencodes])
* Aaron Patterson ([tenderlove])
* https://github.com/ruby/prism
* https://rubygems.org/gems/prism

#### lib/resolv.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/resolv
* https://rubygems.org/gems/resolv

#### lib/securerandom.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/securerandom
* https://rubygems.org/gems/securerandom

#### lib/shellwords.rb

* Akinori MUSHA ([knu])
* https://github.com/ruby/shellwords
* https://rubygems.org/gems/shellwords

#### lib/singleton.rb

* Yukihiro Matsumoto ([matz])
* https://github.com/ruby/singleton
* https://rubygems.org/gems/singleton

#### lib/tempfile.rb

* *No maintainer*
* https://github.com/ruby/tempfile
* https://rubygems.org/gems/tempfile

#### lib/time.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/time
* https://rubygems.org/gems/time

#### lib/timeout.rb

* Yukihiro Matsumoto ([matz])
* https://github.com/ruby/timeout
* https://rubygems.org/gems/timeout

#### lib/tmpdir.rb

* *No maintainer*
* https://github.com/ruby/tmpdir
* https://rubygems.org/gems/tmpdir

#### lib/tsort.rb

* Tanaka Akira ([akr])
* https://github.com/ruby/tsort
* https://rubygems.org/gems/tsort

#### lib/un.rb

* WATANABE Hirofumi ([eban])
* https://github.com/ruby/un
* https://rubygems.org/gems/un

#### lib/uri.rb, lib/uri/*

* NARUSE, Yui ([nurse])
* https://github.com/ruby/uri
* https://rubygems.org/gems/uri

#### lib/yaml.rb, lib/yaml/*

* Aaron Patterson ([tenderlove])
* Hiroshi SHIBATA ([hsbt])
* https://github.com/ruby/yaml
* https://rubygems.org/gems/yaml

#### lib/weakref.rb

* *No maintainer*
* https://github.com/ruby/weakref
* https://rubygems.org/gems/weakref

### Default gems(Extensions) Maintainers

#### ext/cgi

* Nobuyoshi Nakada ([nobu])

#### ext/date

* *No maintainer*
* https://github.com/ruby/date
* https://rubygems.org/gems/date

#### ext/etc

* *No maintainer*
* https://github.com/ruby/etc
* https://rubygems.org/gems/etc

#### ext/fcntl

* *No maintainer*
* https://github.com/ruby/fcntl
* https://rubygems.org/gems/fcntl

#### ext/io/console

* Nobuyuki Nakada ([nobu])
* https://github.com/ruby/io-console
* https://rubygems.org/gems/io-console

#### ext/io/nonblock

* Nobuyuki Nakada ([nobu])
* https://github.com/ruby/io-nonblock
* https://rubygems.org/gems/io-nonblock

#### ext/io/wait

* Nobuyuki Nakada ([nobu])
* https://github.com/ruby/io-wait
* https://rubygems.org/gems/io-wait

#### ext/json

* NARUSE, Yui ([nurse])
* Hiroshi SHIBATA ([hsbt])
* Jean Boussier ([byroot])
* https://github.com/ruby/json
* https://rubygems.org/gems/json

#### ext/openssl

* Kazuki Yamaguchi ([rhenium])
* https://github.com/ruby/openssl
* https://rubygems.org/gems/openssl

#### ext/pathname

* Tanaka Akira ([akr])
* https://github.com/ruby/pathname
* https://rubygems.org/gems/pathname

#### ext/psych

* Aaron Patterson ([tenderlove])
* Hiroshi SHIBATA ([hsbt])
* https://github.com/ruby/psych
* https://rubygems.org/gems/psych

#### ext/stringio

* Nobuyuki Nakada ([nobu])
* https://github.com/ruby/stringio
* https://rubygems.org/gems/stringio

#### ext/strscan

* Kouhei Sutou ([kou])
* https://github.com/ruby/strscan
* https://rubygems.org/gems/strscan

#### ext/zlib

* NARUSE, Yui ([nurse])
* https://github.com/ruby/zlib
* https://rubygems.org/gems/zlib

## Bundled gems upstream repositories and maintainers

The maintanance policy of bundled gems is different from Module Maintainers above.
Please check the policies for each repository.

The ruby core team tries to maintain the repositories with no maintainers.
It may needs to make consensus on ruby-core/ruby-dev before making major changes.

### minitest

* Ryan Davis ([zenspider])
* https://github.com/minitest/minitest
* https://rubygems.org/gems/minitest

### power_assert

* Tsujimoto Kenta ([k-tsj])
* https://github.com/ruby/power_assert
* https://rubygems.org/gems/power_assert

### rake

* Hiroshi SHIBATA ([hsbt])
* https://github.com/ruby/rake
* https://rubygems.org/gems/rake

### test-unit

* Kouhei Sutou ([kou])
* https://github.com/test-unit/test-unit
* https://rubygems.org/gems/test-unit

### rexml

* Kouhei Sutou ([kou])
* https://github.com/ruby/rexml
* https://rubygems.org/gems/rexml

### rss

* Kouhei Sutou ([kou])
* https://github.com/ruby/rss
* https://rubygems.org/gems/rss

### net-ftp

* Shugo Maeda ([shugo])
* https://github.com/ruby/net-ftp
* https://rubygems.org/gems/net-ftp

### net-imap

* Nicholas A. Evans ([nevans])
* https://github.com/ruby/net-imap
* https://rubygems.org/gems/net-imap

### net-pop

* https://github.com/ruby/net-pop
* https://rubygems.org/gems/net-pop

### net-smtp

* TOMITA Masahiro ([tmtm])
* https://github.com/ruby/net-smtp
* https://rubygems.org/gems/net-smtp

### matrix

* Marc-André Lafortune ([marcandre])
* https://github.com/ruby/matrix
* https://rubygems.org/gems/matrix

### prime

* https://github.com/ruby/prime
* https://rubygems.org/gems/prime

### rbs

* Soutaro Matsumoto ([soutaro])
* https://github.com/ruby/rbs
* https://rubygems.org/gems/rbs

### typeprof

* Yusuke Endoh ([mame])
* https://github.com/ruby/typeprof
* https://rubygems.org/gems/typeprof

### debug

* Koichi Sasada ([ko1])
* https://github.com/ruby/debug
* https://rubygems.org/gems/debug

### racc

* Yuichi Kaneko ([yui-knk])
* https://github.com/ruby/racc
* https://rubygems.org/gems/racc

#### mutex_m

* https://github.com/ruby/mutex_m
* https://rubygems.org/gems/mutex_m

#### getoptlong

* https://github.com/ruby/getoptlong
* https://rubygems.org/gems/getoptlong

#### base64

* Yusuke Endoh ([mame])
* https://github.com/ruby/base64
* https://rubygems.org/gems/base64

#### bigdecimal

* Kenta Murata ([mrkn])
* https://github.com/ruby/bigdecimal
* https://rubygems.org/gems/bigdecimal

#### observer

* https://github.com/ruby/observer
* https://rubygems.org/gems/observer

#### abbrev

* Akinori MUSHA ([knu])
* https://github.com/ruby/abbrev
* https://rubygems.org/gems/abbrev

#### resolv-replace

* Akira TANAKA ([akr])
* https://github.com/ruby/resolv-replace
* https://rubygems.org/gems/resolv-replace

#### rinda

* Masatoshi SEKI ([seki])
* https://github.com/ruby/rinda
* https://rubygems.org/gems/rinda

#### drb

* Masatoshi SEKI ([seki])
* https://github.com/ruby/drb
* https://rubygems.org/gems/drb

#### nkf

* Naruse Yusuke ([nurse])
* https://github.com/ruby/nkf
* https://rubygems.org/gems/nkf

#### syslog

* Akinori Musha ([knu])
* https://github.com/ruby/syslog
* https://rubygems.org/gems/syslog

#### csv

* Kouhei Sutou ([kou])
* https://github.com/ruby/csv
* https://rubygems.org/gems/csv

#### ostruct

* Marc-André Lafortune ([marcandre])
* https://github.com/ruby/ostruct
* https://rubygems.org/gems/ostruct

#### pstore

* https://github.com/ruby/pstore
* https://rubygems.org/gems/pstore

#### benchmark

* https://github.com/ruby/benchmark
* https://rubygems.org/gems/benchmark

#### logger

* Naotoshi Seo ([sonots])
* https://github.com/ruby/logger
* https://rubygems.org/gems/logger

#### rdoc

* Stan Lo ([st0012])
* Nobuyoshi Nakada ([nobu])
* https://github.com/ruby/rdoc
* https://rubygems.org/gems/rdoc

#### win32ole

* Masaki Suketa ([suketa])
* https://github.com/ruby/win32ole
* https://rubygems.org/gems/win32ole

#### irb

* Tomoya Ishida ([tompng])
* Stan Lo ([st0012])
* Mari Imaizumi ([ima1zumi])
* HASUMI Hitoshi ([hasumikin])
* https://github.com/ruby/irb
* https://rubygems.org/gems/irb

#### reline

* Tomoya Ishida ([tompng])
* Stan Lo ([st0012])
* Mari Imaizumi ([ima1zumi])
* HASUMI Hitoshi ([hasumikin])
* https://github.com/ruby/reline
* https://rubygems.org/gems/reline

#### readline

* https://github.com/ruby/readline
* https://rubygems.org/gems/readline

#### fiddle

* Kouhei Sutou ([kou])
* https://github.com/ruby/fiddle
* https://rubygems.org/gems/fiddle

#### repl_type_completor

* Tomoya Ishida ([tompng])
* https://github.com/ruby/repl_type_completor
* https://rubygems.org/gems/repl_type_completor

## Platform Maintainers

### mswin64 (Microsoft Windows)

* NAKAMURA Usaku ([unak])

### mingw32 (Minimalist GNU for Windows)

* Nobuyoshi Nakada ([nobu])

### AIX

* Yutaka Kanemoto ([kanemoto])

### FreeBSD

* Akinori MUSHA ([knu])

### Solaris

* Naohisa Goto ([ngoto])

### RHEL, CentOS

* KOSAKI Motohiro ([kosaki])

### macOS

* Kenta Murata ([mrkn])

### OpenBSD

* Jeremy Evans ([jeremyevans])

### cygwin, ...

* **No maintainer**

### WebAssembly/WASI

* Yuta Saito ([kateinoigakukun])

[akr]: https://github.com/akr
[byroot]: https://github.com/byroot
[colby-swandale]: https://github.com/colby-swandale
[drbrain]: https://github.com/drbrain
[duerst]: https://github.com/duerst
[eban]: https://github.com/eban
[eileencodes]: https://github.com/eileencodes
[hasumikin]: https://github.com/hasumikin
[hsbt]: https://github.com/hsbt
[ima1zumi]: https://github.com/ima1zumi
[jeremyevans]: https://github.com/jeremyevans
[k-tsj]: https://github.com/k-tsj
[k0kubun]: https://github.com/k0kubun
[kanemoto]: https://github.com/kanemoto
[kateinoigakukun]: https://github.com/kateinoigakukun
[kddnewton]: https://github.com/kddnewton
[keiju]: https://github.com/keiju
[knu]: https://github.com/knu
[ko1]: https://github.com/ko1
[kosaki]: https://github.com/kosaki
[kou]: https://github.com/kou
[mame]: https://github.com/mame
[marcandre]: https://github.com/marcandre
[matz]: https://github.com/matz
[mrkn]: https://github.com/mrkn
[ngoto]: https://github.com/ngoto
[nobu]: https://github.com/nobu
[nurse]: https://github.com/nurse
[rhenium]: https://github.com/rhenium
[seki]: https://github.com/seki
[suketa]: https://github.com/suketa
[sonots]: https://github.com/sonots
[st0012]: https://github.com/st0012
[tenderlove]: https://github.com/tenderlove
[tompng]: https://github.com/tompng
[unak]: https://github.com/unak
[yuki24]: https://github.com/yuki24
[zenspider]: https://github.com/zenspider
[k-tsj]: https://github.com/k-tsj
[nevans]: https://github.com/nevans
[tmtm]: https://github.com/tmtm
[shugo]: https://github.com/shugo
[soutaro]: https://github.com/soutaro
[yui-knk]: https://github.com/yui-knk
[hasumikin]: https://github.com/hasumikin
[suketa]: https://github.com/suketa
