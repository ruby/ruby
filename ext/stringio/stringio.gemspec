# -*- encoding: utf-8 -*-
# frozen_string_literal: true

source_version = ["", "ext/stringio/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}stringio.c")) {|f|
      f.gets("\n#define STRINGIO_VERSION ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end
Gem::Specification.new do |s|
  s.name = "stringio"
  s.version = source_version

  s.required_rubygems_version = Gem::Requirement.new(">= 2.6")
  s.require_paths = ["lib"]
  s.authors = ["Nobu Nakada"]
  s.description = "Pseudo `IO` class from/to `String`."
  s.email = "nobu@ruby-lang.org"
  s.extensions = ["ext/stringio/extconf.rb"]
  s.files = ["README.md", "ext/stringio/extconf.rb", "ext/stringio/stringio.c"]
  s.homepage = "https://github.com/ruby/stringio"
  s.licenses = ["BSD-2-Clause"]
  s.required_ruby_version = ">= 2.5"
  s.rubygems_version = "2.6.11"
  s.summary = "Pseudo IO on String"

  # s.cert_chain  = %w[certs/nobu.pem]
  # s.signing_key = File.expand_path("~/.ssh/gem-private_key.pem") if $0 =~ /gem\z/

  s.add_development_dependency 'rake-compiler'
end
