# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name          = "custom_name"
  s.version       = "0.1.0"
  s.summary       = "A Rust extension for Ruby"
  s.extensions    = ["ext/custom_name_lib/Cargo.toml"]
  s.authors       = ["Ian Ker-Seymer"]
  s.files         = ["lib/custom_name.rb", "ext/custom_name_lib/Cargo.toml", "ext/custom_name_lib/Cargo.lock", "ext/custom_name_lib/src/lib.rs"]
end
