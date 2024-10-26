version = File.foreach(File.join(__dir__, "lib/json/version.rb")) do |line|
  /^\s*VERSION\s*=\s*'(.*)'/ =~ line and break $1
end rescue nil

spec = Gem::Specification.new do |s|
  java_ext = Gem::Platform === s.platform && s.platform =~ 'java' || RUBY_ENGINE == 'jruby'

  s.name = "json"
  s.version = version

  s.summary = "JSON Implementation for Ruby"
  s.homepage = "https://ruby.github.io/json"
  s.metadata = {
    'bug_tracker_uri'   => 'https://github.com/ruby/json/issues',
    'changelog_uri'     => 'https://github.com/ruby/json/blob/master/CHANGES.md',
    'documentation_uri' => 'https://ruby.github.io/json/doc/index.html',
    'homepage_uri'      => s.homepage,
    'source_code_uri'   => 'https://github.com/ruby/json',
    'wiki_uri'          => 'https://github.com/ruby/json/wiki'
  }

  s.required_ruby_version = Gem::Requirement.new(">= 2.3")

  if java_ext
    s.description = "A JSON implementation as a JRuby extension."
    s.author = "Daniel Luz"
    s.email = "dev+ruby@mernen.com"
  else
    s.description = "This is a JSON implementation as a Ruby extension in C."
    s.authors = ["Florian Frank"]
    s.email = "flori@ping.de"
  end

  s.licenses = ["Ruby"]

  s.extra_rdoc_files = ["README.md"]
  s.rdoc_options = ["--title", "JSON implementation for Ruby", "--main", "README.md"]

  s.files = [
    "CHANGES.md",
    "COPYING",
    "BSDL",
    "LEGAL",
    "README.md",
    "json.gemspec",
    *Dir["lib/**/*.rb"],
  ]

  if java_ext
    s.platform = 'java'
  else
    s.extensions = Dir["ext/json/**/extconf.rb"]
    s.files += Dir["ext/json/**/*.{c,h,rl}"]
  end
end

if RUBY_ENGINE == 'jruby' && $0 == __FILE__
  Gem::Builder.new(spec).build
else
  spec
end
