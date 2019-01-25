begin
  require_relative "lib/rss/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "rss"
  spec.version       = RSS::VERSION
  spec.authors       = ["Kouhei Sutou"]
  spec.email         = ["kou@cozmixng.org"]

  spec.summary       = %q{Family of libraries that support various formats of XML "feeds".}
  spec.description   = %q{Family of libraries that support various formats of XML "feeds".}
  spec.homepage      = "https://github.com/ruby/rss"
  spec.license       = "BSD-2-Clause"

  spec.files         = [
    ".gitignore",
    ".travis.yml",
    "Gemfile",
    "LICENSE.txt",
    "NEWS.md",
    "README.md",
    "Rakefile",
    "lib/rss.rb",
    "lib/rss/0.9.rb",
    "lib/rss/1.0.rb",
    "lib/rss/2.0.rb",
    "lib/rss/atom.rb",
    "lib/rss/content.rb",
    "lib/rss/content/1.0.rb",
    "lib/rss/content/2.0.rb",
    "lib/rss/converter.rb",
    "lib/rss/dublincore.rb",
    "lib/rss/dublincore/1.0.rb",
    "lib/rss/dublincore/2.0.rb",
    "lib/rss/dublincore/atom.rb",
    "lib/rss/image.rb",
    "lib/rss/itunes.rb",
    "lib/rss/maker.rb",
    "lib/rss/maker/0.9.rb",
    "lib/rss/maker/1.0.rb",
    "lib/rss/maker/2.0.rb",
    "lib/rss/maker/atom.rb",
    "lib/rss/maker/base.rb",
    "lib/rss/maker/content.rb",
    "lib/rss/maker/dublincore.rb",
    "lib/rss/maker/entry.rb",
    "lib/rss/maker/feed.rb",
    "lib/rss/maker/image.rb",
    "lib/rss/maker/itunes.rb",
    "lib/rss/maker/slash.rb",
    "lib/rss/maker/syndication.rb",
    "lib/rss/maker/taxonomy.rb",
    "lib/rss/maker/trackback.rb",
    "lib/rss/parser.rb",
    "lib/rss/rexmlparser.rb",
    "lib/rss/rss.rb",
    "lib/rss/slash.rb",
    "lib/rss/syndication.rb",
    "lib/rss/taxonomy.rb",
    "lib/rss/trackback.rb",
    "lib/rss/utils.rb",
    "lib/rss/version.rb",
    "lib/rss/xml-stylesheet.rb",
    "lib/rss/xml.rb",
    "lib/rss/xmlparser.rb",
    "lib/rss/xmlscanner.rb",
    "rss.gemspec",
  ]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
end
