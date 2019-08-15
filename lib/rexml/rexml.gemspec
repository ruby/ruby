begin
  require_relative "lib/rexml/rexml"
rescue LoadError
  # for Ruby core repository
  require_relative "rexml"
end

Gem::Specification.new do |spec|
  spec.name          = "rexml"
  spec.version       = REXML::VERSION
  spec.authors       = ["Kouhei Sutou"]
  spec.email         = ["kou@cozmixng.org"]

  spec.summary       = %q{An XML toolkit for Ruby}
  spec.description   = %q{An XML toolkit for Ruby}
  spec.homepage      = "https://github.com/ruby/rexml"
  spec.license       = "BSD-2-Clause"

  spec.files         = [
    ".gitignore",
    ".travis.yml",
    "Gemfile",
    "LICENSE.txt",
    "NEWS.md",
    "README.md",
    "Rakefile",
    "lib/rexml/attlistdecl.rb",
    "lib/rexml/attribute.rb",
    "lib/rexml/cdata.rb",
    "lib/rexml/child.rb",
    "lib/rexml/comment.rb",
    "lib/rexml/doctype.rb",
    "lib/rexml/document.rb",
    "lib/rexml/dtd/attlistdecl.rb",
    "lib/rexml/dtd/dtd.rb",
    "lib/rexml/dtd/elementdecl.rb",
    "lib/rexml/dtd/entitydecl.rb",
    "lib/rexml/dtd/notationdecl.rb",
    "lib/rexml/element.rb",
    "lib/rexml/encoding.rb",
    "lib/rexml/entity.rb",
    "lib/rexml/formatters/default.rb",
    "lib/rexml/formatters/pretty.rb",
    "lib/rexml/formatters/transitive.rb",
    "lib/rexml/functions.rb",
    "lib/rexml/instruction.rb",
    "lib/rexml/light/node.rb",
    "lib/rexml/namespace.rb",
    "lib/rexml/node.rb",
    "lib/rexml/output.rb",
    "lib/rexml/parent.rb",
    "lib/rexml/parseexception.rb",
    "lib/rexml/parsers/baseparser.rb",
    "lib/rexml/parsers/lightparser.rb",
    "lib/rexml/parsers/pullparser.rb",
    "lib/rexml/parsers/sax2parser.rb",
    "lib/rexml/parsers/streamparser.rb",
    "lib/rexml/parsers/treeparser.rb",
    "lib/rexml/parsers/ultralightparser.rb",
    "lib/rexml/parsers/xpathparser.rb",
    "lib/rexml/quickpath.rb",
    "lib/rexml/rexml.rb",
    "lib/rexml/sax2listener.rb",
    "lib/rexml/security.rb",
    "lib/rexml/source.rb",
    "lib/rexml/streamlistener.rb",
    "lib/rexml/text.rb",
    "lib/rexml/undefinednamespaceexception.rb",
    "lib/rexml/validation/relaxng.rb",
    "lib/rexml/validation/validation.rb",
    "lib/rexml/validation/validationexception.rb",
    "lib/rexml/xmldecl.rb",
    "lib/rexml/xmltokens.rb",
    "lib/rexml/xpath.rb",
    "lib/rexml/xpath_parser.rb",
    "rexml.gemspec",
  ]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
