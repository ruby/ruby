# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "prism"
  spec.version = "0.24.0"
  spec.authors = ["Shopify"]
  spec.email = ["ruby@shopify.com"]

  spec.summary = "Prism Ruby parser"
  spec.homepage = "https://github.com/ruby/prism"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.require_paths = ["lib"]
  spec.files = [
    "BSDmakefile",
    "CHANGELOG.md",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.md",
    "Makefile",
    "README.md",
    "config.yml",
    "docs/build_system.md",
    "docs/configuration.md",
    "docs/cruby_compilation.md",
    "docs/design.md",
    "docs/encoding.md",
    "docs/fuzzing.md",
    "docs/heredocs.md",
    "docs/javascript.md",
    "docs/local_variable_depth.md",
    "docs/mapping.md",
    "docs/parser_translation.md",
    "docs/parsing_rules.md",
    "docs/releasing.md",
    "docs/ripper_translation.md",
    "docs/ruby_api.md",
    "docs/ruby_parser_translation.md",
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
    "include/prism/static_literals.h",
    "include/prism/util/pm_buffer.h",
    "include/prism/util/pm_char.h",
    "include/prism/util/pm_constant_pool.h",
    "include/prism/util/pm_integer.h",
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
    "lib/prism/node_ext.rb",
    "lib/prism/node_inspector.rb",
    "lib/prism/node.rb",
    "lib/prism/pack.rb",
    "lib/prism/parse_result.rb",
    "lib/prism/parse_result/comments.rb",
    "lib/prism/parse_result/newlines.rb",
    "lib/prism/pattern.rb",
    "lib/prism/polyfill/string.rb",
    "lib/prism/serialize.rb",
    "lib/prism/translation.rb",
    "lib/prism/translation/parser.rb",
    "lib/prism/translation/parser33.rb",
    "lib/prism/translation/parser34.rb",
    "lib/prism/translation/parser/compiler.rb",
    "lib/prism/translation/parser/lexer.rb",
    "lib/prism/translation/parser/rubocop.rb",
    "lib/prism/translation/ripper.rb",
    "lib/prism/translation/ripper/sexp.rb",
    "lib/prism/translation/ripper/shim.rb",
    "lib/prism/translation/ruby_parser.rb",
    "lib/prism/visitor.rb",
    "src/diagnostic.c",
    "src/encoding.c",
    "src/node.c",
    "src/pack.c",
    "src/prettyprint.c",
    "src/regexp.c",
    "src/serialize.c",
    "src/static_literals.c",
    "src/token_type.c",
    "src/util/pm_buffer.c",
    "src/util/pm_char.c",
    "src/util/pm_constant_pool.c",
    "src/util/pm_integer.c",
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
    "sig/prism/compiler.rbs",
    "sig/prism/dispatcher.rbs",
    "sig/prism/dot_visitor.rbs",
    "sig/prism/dsl.rbs",
    "sig/prism/mutation_compiler.rbs",
    "sig/prism/node.rbs",
    "sig/prism/node_ext.rbs",
    "sig/prism/pack.rbs",
    "sig/prism/parse_result.rbs",
    "sig/prism/pattern.rbs",
    "sig/prism/serialize.rbs",
    "sig/prism/visitor.rbs",
    "rbi/prism.rbi",
    "rbi/prism/compiler.rbi",
    "rbi/prism/desugar_compiler.rbi",
    "rbi/prism/mutation_compiler.rbi",
    "rbi/prism/node_ext.rbi",
    "rbi/prism/node.rbi",
    "rbi/prism/parse_result.rbi",
    "rbi/prism/translation/parser/compiler.rbi",
    "rbi/prism/translation/ripper.rbi",
    "rbi/prism/translation/ripper/ripper_compiler.rbi",
    "rbi/prism/translation/ruby_parser.rbi",
    "rbi/prism/visitor.rbi"
  ]

  spec.extensions = ["ext/prism/extconf.rb"]
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = "https://github.com/ruby/prism"
  spec.metadata["changelog_uri"] = "https://github.com/ruby/prism/blob/main/CHANGELOG.md"
end
