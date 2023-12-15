require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "bootsnap", require: false
end

require 'bootsnap'
Bootsnap.setup(
  cache_dir:            'tmp/cache',
  ignore_directories:   ['node_modules'],
  development_mode:     true,
  load_path_cache:      true,
  compile_cache_iseq:   true,
  compile_cache_yaml:   true,
  compile_cache_json:   true,
  readonly:             true,
)

require 'csv'
