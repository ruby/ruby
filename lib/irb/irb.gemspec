begin
  require_relative "lib/irb/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "irb"
  spec.version       = IRB::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Interactive Ruby command-line tool for REPL (Read Eval Print Loop).}
  spec.description   = %q{Interactive Ruby command-line tool for REPL (Read Eval Print Loop).}
  spec.homepage      = "https://github.com/ruby/irb"
  spec.license       = "BSD-2-Clause"

  spec.files         = [
    "Gemfile",
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "bin/console",
    "bin/setup",
    "doc/irb/irb-tools.rd.ja",
    "doc/irb/irb.rd.ja",
    "exe/irb",
    "irb.gemspec",
    "lib/irb.rb",
    "lib/irb/cmd/chws.rb",
    "lib/irb/cmd/fork.rb",
    "lib/irb/cmd/help.rb",
    "lib/irb/cmd/load.rb",
    "lib/irb/cmd/nop.rb",
    "lib/irb/cmd/pushws.rb",
    "lib/irb/cmd/subirb.rb",
    "lib/irb/color.rb",
    "lib/irb/completion.rb",
    "lib/irb/context.rb",
    "lib/irb/ext/change-ws.rb",
    "lib/irb/ext/history.rb",
    "lib/irb/ext/loader.rb",
    "lib/irb/ext/multi-irb.rb",
    "lib/irb/ext/save-history.rb",
    "lib/irb/ext/tracer.rb",
    "lib/irb/ext/use-loader.rb",
    "lib/irb/ext/workspaces.rb",
    "lib/irb/extend-command.rb",
    "lib/irb/frame.rb",
    "lib/irb/help.rb",
    "lib/irb/init.rb",
    "lib/irb/input-method.rb",
    "lib/irb/inspector.rb",
    "lib/irb/lc/.document",
    "lib/irb/lc/error.rb",
    "lib/irb/lc/help-message",
    "lib/irb/lc/ja/encoding_aliases.rb",
    "lib/irb/lc/ja/error.rb",
    "lib/irb/lc/ja/help-message",
    "lib/irb/locale.rb",
    "lib/irb/magic-file.rb",
    "lib/irb/notifier.rb",
    "lib/irb/output-method.rb",
    "lib/irb/ruby-lex.rb",
    "lib/irb/ruby-token.rb",
    "lib/irb/ruby_logo.aa",
    "lib/irb/slex.rb",
    "lib/irb/src_encoding.rb",
    "lib/irb/version.rb",
    "lib/irb/workspace.rb",
    "lib/irb/ws-for-case-2.rb",
    "lib/irb/xmp.rb",
    "man/irb.1",
  ]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = Gem::Requirement.new(">= 2.4")

  spec.add_dependency "reline", ">= 0.0.1"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
