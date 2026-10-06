# frozen_string_literal: true

module RegexpEngineSupport
  module_function

  # Whether new Regexp objects in this process are compiled by the Rust
  # engine, as selected by --regexp-engine=rust or the configured default.
  def rust_engine?
    RUBY_DESCRIPTION.include?(" +RUST_REGEXP")
  end

  # Whether this ruby was built with the Rust engine at all.
  def rust_engine_available?
    RbConfig::CONFIG.fetch("RUST_REGEXP_SUPPORT", "no") != "no"
  end
end
