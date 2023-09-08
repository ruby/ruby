# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "yarp"
  spec.version = "0.11.0"
  spec.authors = ["Shopify"]
  spec.email = ["ruby@shopify.com"]

  spec.summary = "Yet Another Ruby Parser"
  spec.homepage = "https://github.com/ruby/yarp"
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
    "docs/mapping.md",
    "docs/ripper.md",
    "docs/ruby_api.md",
    "docs/serialization.md",
    "docs/testing.md",
    "ext/yarp/api_node.c",
    "ext/yarp/api_pack.c",
    "ext/yarp/extension.c",
    "ext/yarp/extension.h",
    "include/yarp.h",
    "include/yarp/ast.h",
    "include/yarp/defines.h",
    "include/yarp/diagnostic.h",
    "include/yarp/enc/yp_encoding.h",
    "include/yarp/node.h",
    "include/yarp/pack.h",
    "include/yarp/parser.h",
    "include/yarp/regexp.h",
    "include/yarp/unescape.h",
    "include/yarp/util/yp_buffer.h",
    "include/yarp/util/yp_char.h",
    "include/yarp/util/yp_constant_pool.h",
    "include/yarp/util/yp_list.h",
    "include/yarp/util/yp_memchr.h",
    "include/yarp/util/yp_newline_list.h",
    "include/yarp/util/yp_state_stack.h",
    "include/yarp/util/yp_string.h",
    "include/yarp/util/yp_string_list.h",
    "include/yarp/util/yp_strpbrk.h",
    "include/yarp/version.h",
    "lib/yarp.rb",
    "lib/yarp/desugar_visitor.rb",
    "lib/yarp/ffi.rb",
    "lib/yarp/lex_compat.rb",
    "lib/yarp/mutation_visitor.rb",
    "lib/yarp/node.rb",
    "lib/yarp/pack.rb",
    "lib/yarp/pattern.rb",
    "lib/yarp/ripper_compat.rb",
    "lib/yarp/serialize.rb",
    "lib/yarp/parse_result/comments.rb",
    "lib/yarp/parse_result/newlines.rb",
    "src/diagnostic.c",
    "src/enc/yp_big5.c",
    "src/enc/yp_euc_jp.c",
    "src/enc/yp_gbk.c",
    "src/enc/yp_shift_jis.c",
    "src/enc/yp_tables.c",
    "src/enc/yp_unicode.c",
    "src/enc/yp_windows_31j.c",
    "src/node.c",
    "src/pack.c",
    "src/prettyprint.c",
    "src/regexp.c",
    "src/serialize.c",
    "src/token_type.c",
    "src/unescape.c",
    "src/util/yp_buffer.c",
    "src/util/yp_char.c",
    "src/util/yp_constant_pool.c",
    "src/util/yp_list.c",
    "src/util/yp_memchr.c",
    "src/util/yp_newline_list.c",
    "src/util/yp_state_stack.c",
    "src/util/yp_string.c",
    "src/util/yp_string_list.c",
    "src/util/yp_strncasecmp.c",
    "src/util/yp_strpbrk.c",
    "src/yarp.c",
    "yarp.gemspec",
  ]

  spec.extensions = ["ext/yarp/extconf.rb"]
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
end
