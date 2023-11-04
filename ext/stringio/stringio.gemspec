# -*- coding: utf-8 -*-
# frozen_string_literal: true

source_version = ["", "ext/stringio/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}stringio.c")) {|f|
      f.gets("\nSTRINGIO_VERSION ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end
Gem::Specification.new do |s|
  s.name = "stringio"
  s.version = source_version

  s.require_paths = ["lib"]
  s.authors = ["Nobu Nakada", "Charles Oliver Nutter"]
  s.description = "Pseudo `IO` class from/to `String`."
  s.email = ["nobu@ruby-lang.org", "headius@headius.com"]
  s.files = ["README.md"]
  jruby = true if Gem::Platform.new('java') =~ s.platform or RUBY_ENGINE == 'jruby'
  if jruby
    s.require_paths = "lib/java"
    s.files += ["lib/java/stringio.rb", "lib/java/stringio.jar"]
    s.platform = "java"
  else
    s.extensions = ["ext/stringio/extconf.rb"]
    s.files += ["ext/stringio/extconf.rb", "ext/stringio/stringio.c"]
  end
  s.homepage = "https://github.com/ruby/stringio"
  s.licenses = ["Ruby", "BSD-2-Clause"]
  s.required_ruby_version = ">= 2.7"
  s.summary = "Pseudo IO on String"

  # s.cert_chain  = %w[certs/nobu.pem]
  # s.signing_key = File.expand_path("~/.ssh/gem-private_key.pem") if $0 =~ /gem\z/
end
