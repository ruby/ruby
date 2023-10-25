source_version = ["", "ext/win32ole/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}win32ole.c")) {|f|
      f.gets("\n#define WIN32OLE_VERSION ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end

Gem::Specification.new do |spec|
  spec.name          = "win32ole"
  spec.version       = source_version
  spec.authors       = ["Masaki Suketa"]
  spec.email         = ["suke@ruby-lang.org"]

  spec.summary       = %q{Provides an interface for OLE Automation in Ruby}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/win32ole"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
