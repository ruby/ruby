Gem::Specification.new do |s|
  s.name          = "custom_name"
  s.version       = "0.1.0"
  s.summary       = "A Rust extension for Ruby"
  s.extensions    = ["Cargo.toml"]
  s.authors       = ["Ian Ker-Seymer"]
  s.files         = ["Cargo.toml", "Cargo.lock", "src/lib.rs"]

  s.metadata["cargo_crate_name"] = "custom-name-ext"
end
