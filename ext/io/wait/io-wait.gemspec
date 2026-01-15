_VERSION = "0.4.0"

Gem::Specification.new do |spec|
  spec.name          = "io-wait"
  spec.version       = _VERSION
  spec.authors       = ["Nobu Nakada", "Charles Oliver Nutter"]
  spec.email         = ["nobu@ruby-lang.org", "headius@headius.com"]

  spec.summary       = %q{Waits until IO is readable or writable without blocking.}
  spec.description   = %q{Waits until IO is readable or writable without blocking.}
  spec.homepage      = "https://github.com/ruby/io-wait"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  jruby = true if Gem::Platform.new('java') =~ spec.platform or RUBY_ENGINE == 'jruby'
  dir, gemspec = File.split(__FILE__)
  excludes = [
    *%w[:^/.git* :^/Gemfile* :^/Rakefile* :^/bin/ :^/test/ :^/rakelib/ :^*.java],
    *(jruby ? %w[:^/ext/io] : %w[:^/ext/java]),
    ":(exclude,literal,top)#{gemspec}"
  ]
  files = IO.popen(%w[git ls-files -z --] + excludes, chdir: dir, &:read).split("\x0")

  spec.files = files
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]

  if jruby
    spec.platform = 'java'
    spec.files << "lib/io/wait.jar"
    spec.require_paths += ["ext/java/lib"]
  else
    spec.extensions    = %w[ext/io/wait/extconf.rb]
  end
end
