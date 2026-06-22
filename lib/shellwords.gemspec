name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1).join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end


Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Akinori MUSHA"]
  spec.email         = ["knu@idaemons.org"]

  spec.summary       = %q{Manipulates strings with word parsing rules of UNIX Bourne shell.}
  spec.description   = %q{Manipulates strings with word parsing rules of UNIX Bourne shell.}
  spec.homepage      = "https://github.com/ruby/shellwords"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  srcdir, gemspec_file = File.split(__FILE__)
  spec.files         = Dir.chdir(srcdir) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:(?:test|spec|features)/|\.git|Rake)}) || f ==  gemspec_file}
  end
  spec.require_paths = ["lib"]
end
