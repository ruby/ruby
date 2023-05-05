source_version = ["", "ext/readline/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}readline.c")) {|f|
      f.gets("\n#define READLINE_VERSION ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end

Gem::Specification.new do |spec|
  spec.name          = "readline-ext"
  spec.version       = source_version
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Provides an interface for GNU Readline and Edit Line (libedit).}
  spec.description   = %q{Provides an interface for GNU Readline and Edit Line (libedit).}
  spec.homepage      = "https://github.com/ruby/readline-ext"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.extensions    = %w[ext/readline/extconf.rb]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>#{IO::NULL}`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
