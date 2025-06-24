# Ruby Standard Library

The Ruby Standard Library is a large collection of classes and modules you can
require in your code to gain additional features.

Below is an overview of the libraries and extensions, followed by a brief description
of each.

## Libraries

- `MakeMakefile`: A module used to generate a Makefile for C extensions
- `RbConfig`: Information about your Ruby configuration and build
- `Gem`: A package management framework for Ruby

## Extensions

- `Coverage`: Provides coverage measurement for Ruby
- `Monitor`: Provides a reentrant mutex
- `objspace`: Extends the ObjectSpace module to add methods for internal statistics
- `PTY`: Creates and manages pseudo-terminals
- `Ripper`: Provides an interface for parsing Ruby programs into S-expressions
- `Socket`: Accesses underlying OS socket implementations

# Default gems

- Default gems are shipped with Ruby releases and also available as rubygems.
- Default gems are not uninstallable from the Ruby installation.
- Default gems can be updated using rubygems.
    - e.g. `gem update json`
- Default gems can be used with bundler environments like `unbundled_env`.
- Default gems can be used at any version in a Gemfile.
    - e.g. `gem "json", ">= 2.6"`

## Libraries

- Bundler ([GitHub][bundler]): Manage your Ruby application's gem dependencies
- Delegator ([GitHub][delegate]): Provides three abilities to delegate method calls to an object
- DidYouMean ([GitHub][did_you_mean]): "Did you mean?" experience in Ruby
- English ([GitHub][English]): Provides references to special global variables with less cryptic names
- ERB ([GitHub][erb]): An easy-to-use but powerful templating system for Ruby
- ErrorHighlight ([GitHub][error_highlight]): Highlight error locations in your code
- FileUtils ([GitHub][fileutils]): Several file utility methods for copying, moving, removing, etc.
- Find ([GitHub][find]): This module supports top-down traversal of a set of file paths
- Forwardable ([GitHub][forwardable]): Provides delegation of specified methods to a designated object
- IPAddr ([GitHub][ipaddr]): Provides methods to manipulate IPv4 and IPv6 IP addresses
- OptionParser ([GitHub][optparse]): Ruby-oriented class for command-line option analysis
- Net::HTTP ([GitHub][net-http]): HTTP client API for Ruby
- Open3 ([GitHub][open3]): Provides access to stdin, stdout, and stderr when running other programs
- OpenURI ([GitHub][open-uri]): An easy-to-use wrapper for URI::HTTP, URI::HTTPS, and URI::FTP
- PP ([GitHub][pp]): Provides a PrettyPrinter for Ruby objects
- PrettyPrint ([GitHub][prettyprint]): Implements a pretty printing algorithm for readable structure
- Prism ([GitHub][prism]): A portable, error-tolerant Ruby parser
- Resolv ([GitHub][resolv]): Thread-aware DNS resolver library in Ruby
- SecureRandom ([GitHub][securerandom]): Interface for a secure random number generator
- Shellwords ([GitHub][shellwords]): Manipulates strings with the word parsing rules of the UNIX Bourne shell
- Singleton ([GitHub][singleton]): Implementation of the Singleton pattern for Ruby
- Tempfile ([GitHub][tempfile]): A utility class for managing temporary files
- Time ([GitHub][time]): Extends the Time class with methods for parsing and conversion
- Timeout ([GitHub][timeout]): Auto-terminate potentially long-running operations in Ruby
- TmpDir ([GitHub][tmpdir]): Extends the Dir class to manage the OS temporary file path
- TSort ([GitHub][tsort]): Topological sorting using Tarjan's algorithm
- UN ([GitHub][un]): Utilities to replace common UNIX commands
- URI ([GitHub][uri]): A Ruby module providing support for Uniform Resource Identifiers
- YAML ([GitHub][yaml]): The Ruby client library for the Psych YAML implementation
- WeakRef ([GitHub][weakref]): Allows a referenced object to be garbage-collected

## Extensions

- Date ([GitHub][date]): Represents dates, with a subclass for dates with time and timezones
- Digest ([GitHub][digest]): Provides a framework for message digest libraries
- Etc ([GitHub][etc]): Provides access to information typically stored in the UNIX /etc directory
- Fcntl ([GitHub][fcntl]): Loads constants defined in the OS fcntl.h C header file
- IO.console ([GitHub][io-console]): Extensions for the IO class, including `IO.console`, `IO.winsize`, etc.
- JSON ([GitHub][json]): Implements JavaScript Object Notation for Ruby
- OpenSSL ([GitHub][openssl]): Provides SSL, TLS, and general-purpose cryptography for Ruby
- Pathname ([GitHub][pathname]): Representation of the name of a file or directory on the filesystem
- Psych ([GitHub][psych]): A YAML parser and emitter for Ruby
- StringIO ([GitHub][stringio]): Pseudo-I/O on String objects
- StringScanner ([GitHub][strscan]): Provides lexical scanning operations on a String
- Zlib ([GitHub][zlib]): Ruby interface for the zlib compression/decompression library

# Bundled gems

- Bundled gems are shipped with Ruby releases and also available as rubygems.
    - They are only bundled with Ruby releases.
    - They can be uninstalled from the Ruby installation.
    - They need to be declared in a Gemfile when used with bundler.

## Libraries

- [minitest]: A test library supporting TDD, BDD, mocking, and benchmarking
- [power_assert]: Power Assert for Ruby
- [rake][rake-doc] ([GitHub][rake]): Ruby build program with capabilities similar to make
- [test-unit]: A compatibility layer for MiniTest
- [rexml][rexml-doc] ([GitHub][rexml]): An XML toolkit for Ruby
- [rss]: A family of libraries supporting various XML-based "feeds"
- [net-ftp]: Support for the File Transfer Protocol
- [net-imap]: Ruby client API for the Internet Message Access Protocol
- [net-pop]: Ruby client library for POP3
- [net-smtp]: Simple Mail Transfer Protocol client library for Ruby
- [matrix]: Represents a mathematical matrix
- [prime]: Prime numbers and factorization library
- [rbs]: RBS is a language to describe the structure of Ruby programs
- [typeprof]: A type analysis tool for Ruby code based on abstract interpretation
- [debug]: Debugging functionality for Ruby
- [racc][racc-doc] ([GitHub][racc]): A LALR(1) parser generator written in Ruby
- [mutex_m]: Mixin to extend objects to be handled like a Mutex
- [getoptlong]: Parse command line options similar to the GNU C getopt_long()
- [base64]: Support for encoding and decoding binary data using a Base64 representation
- [bigdecimal]: Provides arbitrary-precision floating point decimal arithmetic
- [observer]: Provides a mechanism for the publish/subscribe pattern in Ruby
- [abbrev]: Calculates a set of unique abbreviations for a given set of strings
- [resolv-replace]: Replace Socket DNS with Resolv
- [rinda]: The Linda distributed computing paradigm in Ruby
- [drb]: Distributed object system for Ruby
- [nkf]: Ruby extension for the Network Kanji Filter
- [syslog]: Ruby interface for the POSIX system logging facility
- [csv][csv-doc] ([GitHub][csv]): Provides an interface to read and write CSV files and data
- [ostruct]: A class to build custom data structures, similar to a Hash
- [benchmark]: Provides methods to measure and report the time used to execute code
- [logger][logger-doc] ([GitHub][logger]): Provides a simple logging utility for outputting messages
- [pstore]: Implements a file-based persistence mechanism based on a Hash
- [win32ole]: Provides an interface for OLE Automation in Ruby
- [reline][reline-doc] ([GitHub][reline]): GNU Readline and Editline in a pure Ruby implementation
- [readline]: Wrapper for the Readline extension and Reline
- [fiddle]: A libffi wrapper for Ruby

## Tools

- [IRB][irb-doc] ([GitHub][irb]): Interactive Ruby command-line tool for REPL (Read Eval Print Loop)
- [RDoc][rdoc-doc] ([GitHub][rdoc]): Documentation generator for Ruby

[abbrev]: https://github.com/ruby/abbrev
[base64]: https://github.com/ruby/base64
[benchmark]: https://github.com/ruby/benchmark
[bigdecimal]: https://github.com/ruby/bigdecimal
[bundler]: https://github.com/rubygems/rubygems
[csv]: https://github.com/ruby/csv
[date]: https://github.com/ruby/date
[debug]: https://github.com/ruby/debug
[delegate]: https://github.com/ruby/delegate
[did_you_mean]: https://github.com/ruby/did_you_mean
[digest]: https://github.com/ruby/digest
[drb]: https://github.com/ruby/drb
[English]: https://github.com/ruby/English
[erb]: https://github.com/ruby/erb
[error_highlight]: https://github.com/ruby/error_highlight
[etc]: https://github.com/ruby/etc
[fcntl]: https://github.com/ruby/fcntl
[fiddle]: https://github.com/ruby/fiddle
[fileutils]: https://github.com/ruby/fileutils
[find]: https://github.com/ruby/find
[forwardable]: https://github.com/ruby/forwardable
[getoptlong]: https://github.com/ruby/getoptlong
[io-console]: https://github.com/ruby/io-console
[ipaddr]: https://github.com/ruby/ipaddr
[irb]: https://github.com/ruby/irb
[json]: https://github.com/ruby/json
[logger]: https://github.com/ruby/logger
[matrix]: https://github.com/ruby/matrix
[minitest]: https://github.com/seattlerb/minitest
[mutex_m]: https://github.com/ruby/mutex_m
[net-ftp]: https://github.com/ruby/net-ftp
[net-http]: https://github.com/ruby/net-http
[net-imap]: https://github.com/ruby/net-imap
[net-pop]: https://github.com/ruby/net-pop
[net-smtp]: https://github.com/ruby/net-smtp
[nkf]: https://github.com/ruby/nkf
[observer]: https://github.com/ruby/observer
[open-uri]: https://github.com/ruby/open-uri
[open3]: https://github.com/ruby/open3
[openssl]: https://github.com/ruby/openssl
[optparse]: https://github.com/ruby/optparse
[ostruct]: https://github.com/ruby/ostruct
[pathname]: https://github.com/ruby/pathname
[power_assert]: https://github.com/ruby/power_assert
[pp]: https://github.com/ruby/pp
[prettyprint]: https://github.com/ruby/prettyprint
[prime]: https://github.com/ruby/prime
[prism]: https://github.com/ruby/prism
[pstore]: https://github.com/ruby/pstore
[psych]: https://github.com/ruby/psych
[racc]: https://github.com/ruby/racc
[rake]: https://github.com/ruby/rake
[rbs]: https://github.com/ruby/rbs
[rdoc]: https://github.com/ruby/rdoc
[readline]: https://github.com/ruby/readline
[reline]: https://github.com/ruby/reline
[resolv-replace]: https://github.com/ruby/resolv-replace
[resolv]: https://github.com/ruby/resolv
[rexml]: https://github.com/ruby/rexml
[rinda]: https://github.com/ruby/rinda
[rss]: https://github.com/ruby/rss
[securerandom]: https://github.com/ruby/securerandom
[shellwords]: https://github.com/ruby/shellwords
[singleton]: https://github.com/ruby/singleton
[stringio]: https://github.com/ruby/stringio
[strscan]: https://github.com/ruby/strscan
[syslog]: https://github.com/ruby/syslog
[tempfile]: https://github.com/ruby/tempfile
[test-unit]: https://github.com/test-unit/test-unit
[time]: https://github.com/ruby/time
[timeout]: https://github.com/ruby/timeout
[tmpdir]: https://github.com/ruby/tmpdir
[tsort]: https://github.com/ruby/tsort
[typeprof]: https://github.com/ruby/typeprof
[un]: https://github.com/ruby/un
[uri]: https://github.com/ruby/uri
[weakref]: https://github.com/ruby/weakref
[win32ole]: https://github.com/ruby/win32ole
[yaml]: https://github.com/ruby/yaml
[zlib]: https://github.com/ruby/zlib

[reline-doc]: https://ruby.github.io/reline/
[rake-doc]: https://ruby.github.io/rake/
[irb-doc]: https://ruby.github.io/irb/
[rdoc-doc]: https://ruby.github.io/rdoc/
[logger-doc]: https://ruby.github.io/logger/
[racc-doc]: https://ruby.github.io/racc/
[csv-doc]: https://ruby.github.io/csv/
[rexml-doc]: https://ruby.github.io/rexml/
