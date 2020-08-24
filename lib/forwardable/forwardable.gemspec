# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Provides delegation of specified methods to a designated object.}
  spec.description   = %q{Provides delegation of specified methods to a designated object.}
  spec.homepage      = "https://github.com/ruby/forwardable"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.required_ruby_version = '>= 2.4.0'
  spec.files         = ["forwardable.gemspec", "lib/forwardable.rb", "lib/forwardable/impl.rb", "lib/forwardable/version.rb"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
