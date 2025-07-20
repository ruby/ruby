_VERSION = "0.3.1.1"

Gem::Specification.new do |spec|
  spec.name          = "io-wait"
  spec.version       = _VERSION
  spec.authors       = ["Nobu Nakada", "Charles Oliver Nutter"]
  spec.email         = ["nobu@ruby-lang.org", "headius@headius.com"]

  spec.summary       = %q{Waits until IO is readable or writable without blocking.}
  spec.description   = %q{Waits until IO is readable or writable without blocking.}
  spec.homepage      = "https://github.com/ruby/io-wait"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      File.identical?(f, __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features|rakelib)/|\.(?:git|travis|circleci)|appveyor|Rakefile)})
    end
  end
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]

  jruby = true if Gem::Platform.new('java') =~ spec.platform or RUBY_ENGINE == 'jruby'
  spec.files.delete_if do |f|
    f.end_with?(".java") or
      f.start_with?("ext/") && (jruby ^ f.start_with?("ext/java/"))
  end
  if jruby
    spec.platform = 'java'
    spec.files << "lib/io/wait.jar"
    spec.require_paths += ["ext/java/lib"]
  else
    spec.extensions    = %w[ext/io/wait/extconf.rb]
  end
end
