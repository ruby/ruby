# frozen_string_literal: true

begin
  require_relative "lib/bundler/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = Bundler::VERSION
  s.license     = "MIT"
  s.authors     = [
    "Yehuda Katz", "Carl Lerche", "André Arko", "Terence Lee", "Tim Moore",
    "Jessica Lynn Suttles", "Hiroshi SHIBATA", "André Medeiros", "Samuel Giddins", "David Rodríguez",
    "James Wen", "Chris Morris", "Colby Swandale", "Grey Baker", "Stephanie Morillo"
  ]
  s.email = [
    "wycats@gmail.com", "me@carllerche.com", "andre@arko.net", "hone02@gmail.com", "tmoore@incrementalism.net",
    "jlsuttles@gmail.com", "hsbt@ruby-lang.org", "me@andremedeiros.info", "segiddins@segiddins.me", "deivid.rodriguez@riseup.net",
    "jrw2175@columbia.edu", "chrismo@clabs.org", "colby@rubygems.org", "greysteil@gmail.com", ""
  ]
  s.homepage    = "https://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  s.metadata = {
    "bug_tracker_uri" => "https://github.com/ruby/rubygems/issues?q=is%3Aopen+is%3Aissue+label%3ABundler",
    "changelog_uri" => "https://github.com/ruby/rubygems/blob/master/CHANGELOG-bundler.md",
    "homepage_uri" => "https://bundler.io/",
    "source_code_uri" => "https://github.com/ruby/rubygems",
  }

  s.required_ruby_version     = ">= 3.2.0"

  # It should match the RubyGems version shipped with `required_ruby_version` above
  s.required_rubygems_version = ">= 3.4.1"

  s.files = Dir.glob("lib/bundler{.rb,/**/*}", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }

  # Bundler reuses RubyGems' vendored URI, SecureRandom and PubGrub, its
  # pure-Ruby YAML serializer, its compact index client and its credential
  # store. Ship a copy under lib/rubygems so Bundler stays self-contained on
  # RubyGems versions that predate them.
  s.files += Dir.glob("lib/rubygems/vendor/uri/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
  s.files += Dir.glob("lib/rubygems/vendor/securerandom/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
  s.files += Dir.glob("lib/rubygems/vendor/pub_grub/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
  s.files += Dir.glob("lib/rubygems/yaml_serializer.rb")
  s.files += Dir.glob("lib/rubygems/compact_index_client{.rb,/**/*}", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
  s.files += Dir.glob("lib/rubygems/credential_store{.rb,/**/*}", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }

  # include the gemspec itself because warbler breaks w/o it
  s.files += %w[lib/bundler/bundler.gemspec]

  # These live next to the gemspec when Bundler ships as a gem, but not when
  # it is synced into Ruby core, where the gemspec moves under lib/bundler.
  s.files += %w[CHANGELOG-bundler.md LICENSE-bundler.md README-bundler.md].select {|f| File.file?(f) }
  s.bindir        = "exe"
  s.executables   = %w[bundle bundler]
  s.require_paths = ["lib"]
end
