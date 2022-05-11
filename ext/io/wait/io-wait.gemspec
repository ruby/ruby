_VERSION = "0.2.3"

Gem::Specification.new do |spec|
  spec.name          = "io-wait"
  spec.version       = _VERSION
  spec.authors       = ["Nobu Nakada"]
  spec.email         = ["nobu@ruby-lang.org"]

  spec.summary       = %q{Waits until IO is readable or writable without blocking.}
  spec.description   = %q{Waits until IO is readable or writable without blocking.}
  spec.homepage      = "https://github.com/ruby/io-wait"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features|rakelib)/|\.(?:git|travis|circleci)|appveyor|Rakefile)})
    end
  end
  spec.extensions    = %w[ext/io/wait/extconf.rb]
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
