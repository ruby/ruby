# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "prism"
  spec.version = "0.19.0"
  spec.authors = ["Shopify"]
  spec.email = ["ruby@shopify.com"]

  spec.summary = "Prism Ruby parser"
  spec.homepage = "https://github.com/ruby/prism"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.require_paths = ["lib"]
  spec.files = [
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.md",
    "Makefile",
    "README.md",
    "config.yml",
    "docs/build_system.md",
    "docs/building.md",
    "docs/configuration.md",
    "docs/design.md",
    "docs/encoding.md",
    "docs/fuzzing.md",
    "docs/heredocs.md",
    "docs/javascript.md",
    "docs/local_variable_depth.md",
    "docs/mapping.md",
    "docs/releasing.md",
    "docs/ripper.md",
    "docs/ruby_api.md",
    "docs/serialization.md",
    "docs/testing.md",
    "ext/prism/api_node.c",
    "ext/prism/api_pack.c",
    "ext/prism/extension.c",
    "ext/prism/extension.h",
    "include/prism.h",
    "include/prism/ast.h",
    "include/prism/defines.h",
    "include/prism/diagnostic.h",
    "include/prism/encoding.h",
    "include/prism/node.h",
    "include/prism/options.h",
    "include/prism/pack.h",
    "include/prism/parser.h",
    "include/prism/prettyprint.h",
    "include/prism/regexp.h",
    "include/prism/util/pm_buffer.h",
    "include/prism/util/pm_char.h",
    "include/prism/util/pm_constant_pool.h",
    "include/prism/util/pm_list.h",
    "include/prism/util/pm_memchr.h",
    "include/prism/util/pm_newline_list.h",
    "include/prism/util/pm_state_stack.h",
    "include/prism/util/pm_strncasecmp.h",
    "include/prism/util/pm_string.h",
    "include/prism/util/pm_string_list.h",
    "include/prism/util/pm_strpbrk.h",
    "include/prism/version.h",
    "lib/prism.rb",
    "lib/prism/compiler.rb",
    "lib/prism/debug.rb",
    "lib/prism/desugar_compiler.rb",
    "lib/prism/dispatcher.rb",
    "lib/prism/dot_visitor.rb",
    "lib/prism/dsl.rb",
    "lib/prism/ffi.rb",
    "lib/prism/lex_compat.rb",
    "lib/prism/mutation_compiler.rb",
    "lib/prism/node.rb",
    "lib/prism/node_ext.rb",
    "lib/prism/node_inspector.rb",
    "lib/prism/pack.rb",
    "lib/prism/parse_result.rb",
    "lib/prism/pattern.rb",
    "lib/prism/ripper_compat.rb",
    "lib/prism/serialize.rb",
    "lib/prism/parse_result/comments.rb",
    "lib/prism/parse_result/newlines.rb",
    "lib/prism/visitor.rb",
    "src/diagnostic.c",
    "src/encoding.c",
    "src/node.c",
    "src/pack.c",
    "src/prettyprint.c",
    "src/regexp.c",
    "src/serialize.c",
    "src/token_type.c",
    "src/util/pm_buffer.c",
    "src/util/pm_char.c",
    "src/util/pm_constant_pool.c",
    "src/util/pm_list.c",
    "src/util/pm_memchr.c",
    "src/util/pm_newline_list.c",
    "src/util/pm_state_stack.c",
    "src/util/pm_string.c",
    "src/util/pm_string_list.c",
    "src/util/pm_strncasecmp.c",
    "src/util/pm_strpbrk.c",
    "src/options.c",
    "src/prism.c",
    "prism.gemspec",
    "sig/prism.rbs",
    "sig/prism_static.rbs",
    "rbi/prism.rbi",
    "rbi/prism_static.rbi"
  ]

  spec.extensions = ["ext/prism/extconf.rb"]
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/ruby/prism"
  spec.metadata["changelog_uri"] = "https://github.com/ruby/prism/blob/main/CHANGELOG.md"
end
