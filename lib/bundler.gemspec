# coding: utf-8
# frozen_string_literal: true

require File.expand_path("../bundler/version", __FILE__)
require "shellwords"

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = Bundler::VERSION
  s.license     = "MIT"
  s.authors     = [
    "André Arko", "Samuel Giddins", "Chris Morris", "James Wen", "Tim Moore",
    "André Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
    "Yehuda Katz"
  ]
  s.email       = ["team@bundler.io"]
  s.homepage    = "http://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "http://github.com/bundler/bundler/issues",
      "changelog_uri" => "https://github.com/bundler/bundler/blob/master/CHANGELOG.md",
      "homepage_uri" => "https://bundler.io/",
      "source_code_uri" => "http://github.com/bundler/bundler/",
    }
  end

  if s.version >= Gem::Version.new("2.a".dup)
    s.required_ruby_version     = ">= 2.3.0"
    s.required_rubygems_version = ">= 2.5.0"
  else
    s.required_ruby_version     = ">= 1.8.7"
    s.required_rubygems_version = ">= 1.3.6"
  end

  s.add_development_dependency "automatiek", "~> 0.1.0"
  s.add_development_dependency "mustache",   "0.99.6"
  s.add_development_dependency "rake",       "~> 10.0"
  s.add_development_dependency "rdiscount",  "~> 2.2"
  s.add_development_dependency "ronn",       "~> 0.7.3"
  s.add_development_dependency "rspec",      "~> 3.6"

  s.files = %w[
    exe/bundle
    exe/bundle_ruby
    exe/bundler
    lib/bundler.rb
    lib/bundler/build_metadata.rb
    lib/bundler/capistrano.rb
    lib/bundler/cli.rb
    lib/bundler/cli/add.rb
    lib/bundler/cli/binstubs.rb
    lib/bundler/cli/cache.rb
    lib/bundler/cli/check.rb
    lib/bundler/cli/clean.rb
    lib/bundler/cli/common.rb
    lib/bundler/cli/config.rb
    lib/bundler/cli/console.rb
    lib/bundler/cli/doctor.rb
    lib/bundler/cli/exec.rb
    lib/bundler/cli/gem.rb
    lib/bundler/cli/info.rb
    lib/bundler/cli/init.rb
    lib/bundler/cli/inject.rb
    lib/bundler/cli/install.rb
    lib/bundler/cli/issue.rb
    lib/bundler/cli/list.rb
    lib/bundler/cli/lock.rb
    lib/bundler/cli/open.rb
    lib/bundler/cli/outdated.rb
    lib/bundler/cli/package.rb
    lib/bundler/cli/platform.rb
    lib/bundler/cli/plugin.rb
    lib/bundler/cli/pristine.rb
    lib/bundler/cli/show.rb
    lib/bundler/cli/update.rb
    lib/bundler/cli/viz.rb
    lib/bundler/compact_index_client.rb
    lib/bundler/compact_index_client/cache.rb
    lib/bundler/compact_index_client/updater.rb
    lib/bundler/compatibility_guard.rb
    lib/bundler/constants.rb
    lib/bundler/current_ruby.rb
    lib/bundler/definition.rb
    lib/bundler/dep_proxy.rb
    lib/bundler/dependency.rb
    lib/bundler/deployment.rb
    lib/bundler/deprecate.rb
    lib/bundler/dsl.rb
    lib/bundler/endpoint_specification.rb
    lib/bundler/env.rb
    lib/bundler/environment_preserver.rb
    lib/bundler/errors.rb
    lib/bundler/feature_flag.rb
    lib/bundler/fetcher.rb
    lib/bundler/fetcher/base.rb
    lib/bundler/fetcher/compact_index.rb
    lib/bundler/fetcher/dependency.rb
    lib/bundler/fetcher/downloader.rb
    lib/bundler/fetcher/index.rb
    lib/bundler/friendly_errors.rb
    lib/bundler/gem_helper.rb
    lib/bundler/gem_helpers.rb
    lib/bundler/gem_remote_fetcher.rb
    lib/bundler/gem_tasks.rb
    lib/bundler/gem_version_promoter.rb
    lib/bundler/gemdeps.rb
    lib/bundler/graph.rb
    lib/bundler/index.rb
    lib/bundler/injector.rb
    lib/bundler/inline.rb
    lib/bundler/installer.rb
    lib/bundler/installer/gem_installer.rb
    lib/bundler/installer/parallel_installer.rb
    lib/bundler/installer/standalone.rb
    lib/bundler/lazy_specification.rb
    lib/bundler/lockfile_generator.rb
    lib/bundler/lockfile_parser.rb
    lib/bundler/match_platform.rb
    lib/bundler/mirror.rb
    lib/bundler/plugin.rb
    lib/bundler/plugin/api.rb
    lib/bundler/plugin/api/source.rb
    lib/bundler/plugin/dsl.rb
    lib/bundler/plugin/index.rb
    lib/bundler/plugin/installer.rb
    lib/bundler/plugin/installer/git.rb
    lib/bundler/plugin/installer/rubygems.rb
    lib/bundler/plugin/source_list.rb
    lib/bundler/process_lock.rb
    lib/bundler/psyched_yaml.rb
    lib/bundler/remote_specification.rb
    lib/bundler/resolver.rb
    lib/bundler/resolver/spec_group.rb
    lib/bundler/retry.rb
    lib/bundler/ruby_dsl.rb
    lib/bundler/ruby_version.rb
    lib/bundler/rubygems_ext.rb
    lib/bundler/rubygems_gem_installer.rb
    lib/bundler/rubygems_integration.rb
    lib/bundler/runtime.rb
    lib/bundler/settings.rb
    lib/bundler/settings/validator.rb
    lib/bundler/setup.rb
    lib/bundler/shared_helpers.rb
    lib/bundler/similarity_detector.rb
    lib/bundler/source.rb
    lib/bundler/source/gemspec.rb
    lib/bundler/source/git.rb
    lib/bundler/source/git/git_proxy.rb
    lib/bundler/source/metadata.rb
    lib/bundler/source/path.rb
    lib/bundler/source/path/installer.rb
    lib/bundler/source/rubygems.rb
    lib/bundler/source/rubygems/remote.rb
    lib/bundler/source_list.rb
    lib/bundler/spec_set.rb
    lib/bundler/ssl_certs/.document
    lib/bundler/ssl_certs/certificate_manager.rb
    lib/bundler/ssl_certs/index.rubygems.org/GlobalSignRootCA.pem
    lib/bundler/ssl_certs/rubygems.global.ssl.fastly.net/DigiCertHighAssuranceEVRootCA.pem
    lib/bundler/ssl_certs/rubygems.org/AddTrustExternalCARoot.pem
    lib/bundler/stub_specification.rb
    lib/bundler/templates/Executable
    lib/bundler/templates/Executable.bundler
    lib/bundler/templates/Executable.standalone
    lib/bundler/templates/Gemfile
    lib/bundler/templates/gems.rb
    lib/bundler/templates/newgem/CODE_OF_CONDUCT.md.tt
    lib/bundler/templates/newgem/Gemfile.tt
    lib/bundler/templates/newgem/LICENSE.txt.tt
    lib/bundler/templates/newgem/README.md.tt
    lib/bundler/templates/newgem/Rakefile.tt
    lib/bundler/templates/newgem/bin/console.tt
    lib/bundler/templates/newgem/bin/setup.tt
    lib/bundler/templates/newgem/exe/newgem.tt
    lib/bundler/templates/newgem/ext/newgem/extconf.rb.tt
    lib/bundler/templates/newgem/ext/newgem/newgem.c.tt
    lib/bundler/templates/newgem/ext/newgem/newgem.h.tt
    lib/bundler/templates/newgem/gitignore.tt
    lib/bundler/templates/newgem/lib/newgem.rb.tt
    lib/bundler/templates/newgem/lib/newgem/version.rb.tt
    lib/bundler/templates/newgem/newgem.gemspec.tt
    lib/bundler/templates/newgem/rspec.tt
    lib/bundler/templates/newgem/spec/newgem_spec.rb.tt
    lib/bundler/templates/newgem/spec/spec_helper.rb.tt
    lib/bundler/templates/newgem/test/newgem_test.rb.tt
    lib/bundler/templates/newgem/test/test_helper.rb.tt
    lib/bundler/templates/newgem/travis.yml.tt
    lib/bundler/ui.rb
    lib/bundler/ui/rg_proxy.rb
    lib/bundler/ui/shell.rb
    lib/bundler/ui/silent.rb
    lib/bundler/uri_credentials_filter.rb
    lib/bundler/vendor/fileutils/lib/fileutils.rb
    lib/bundler/vendor/molinillo/lib/molinillo.rb
    lib/bundler/vendor/molinillo/lib/molinillo/compatibility.rb
    lib/bundler/vendor/molinillo/lib/molinillo/delegates/resolution_state.rb
    lib/bundler/vendor/molinillo/lib/molinillo/delegates/specification_provider.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/action.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/add_edge_no_circular.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/add_vertex.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/delete_edge.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/detach_vertex_named.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/log.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/set_payload.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/tag.rb
    lib/bundler/vendor/molinillo/lib/molinillo/dependency_graph/vertex.rb
    lib/bundler/vendor/molinillo/lib/molinillo/errors.rb
    lib/bundler/vendor/molinillo/lib/molinillo/gem_metadata.rb
    lib/bundler/vendor/molinillo/lib/molinillo/modules/specification_provider.rb
    lib/bundler/vendor/molinillo/lib/molinillo/modules/ui.rb
    lib/bundler/vendor/molinillo/lib/molinillo/resolution.rb
    lib/bundler/vendor/molinillo/lib/molinillo/resolver.rb
    lib/bundler/vendor/molinillo/lib/molinillo/state.rb
    lib/bundler/vendor/net-http-persistent/lib/net/http/faster.rb
    lib/bundler/vendor/net-http-persistent/lib/net/http/persistent.rb
    lib/bundler/vendor/net-http-persistent/lib/net/http/persistent/ssl_reuse.rb
    lib/bundler/vendor/thor/lib/thor.rb
    lib/bundler/vendor/thor/lib/thor/actions.rb
    lib/bundler/vendor/thor/lib/thor/actions/create_file.rb
    lib/bundler/vendor/thor/lib/thor/actions/create_link.rb
    lib/bundler/vendor/thor/lib/thor/actions/directory.rb
    lib/bundler/vendor/thor/lib/thor/actions/empty_directory.rb
    lib/bundler/vendor/thor/lib/thor/actions/file_manipulation.rb
    lib/bundler/vendor/thor/lib/thor/actions/inject_into_file.rb
    lib/bundler/vendor/thor/lib/thor/base.rb
    lib/bundler/vendor/thor/lib/thor/command.rb
    lib/bundler/vendor/thor/lib/thor/core_ext/hash_with_indifferent_access.rb
    lib/bundler/vendor/thor/lib/thor/core_ext/io_binary_read.rb
    lib/bundler/vendor/thor/lib/thor/core_ext/ordered_hash.rb
    lib/bundler/vendor/thor/lib/thor/error.rb
    lib/bundler/vendor/thor/lib/thor/group.rb
    lib/bundler/vendor/thor/lib/thor/invocation.rb
    lib/bundler/vendor/thor/lib/thor/line_editor.rb
    lib/bundler/vendor/thor/lib/thor/line_editor/basic.rb
    lib/bundler/vendor/thor/lib/thor/line_editor/readline.rb
    lib/bundler/vendor/thor/lib/thor/parser.rb
    lib/bundler/vendor/thor/lib/thor/parser/argument.rb
    lib/bundler/vendor/thor/lib/thor/parser/arguments.rb
    lib/bundler/vendor/thor/lib/thor/parser/option.rb
    lib/bundler/vendor/thor/lib/thor/parser/options.rb
    lib/bundler/vendor/thor/lib/thor/rake_compat.rb
    lib/bundler/vendor/thor/lib/thor/runner.rb
    lib/bundler/vendor/thor/lib/thor/shell.rb
    lib/bundler/vendor/thor/lib/thor/shell/basic.rb
    lib/bundler/vendor/thor/lib/thor/shell/color.rb
    lib/bundler/vendor/thor/lib/thor/shell/html.rb
    lib/bundler/vendor/thor/lib/thor/util.rb
    lib/bundler/vendor/thor/lib/thor/version.rb
    lib/bundler/vendored_fileutils.rb
    lib/bundler/vendored_molinillo.rb
    lib/bundler/vendored_persistent.rb
    lib/bundler/vendored_thor.rb
    lib/bundler/version.rb
    lib/bundler/version_ranges.rb
    lib/bundler/vlad.rb
    lib/bundler/worker.rb
    lib/bundler/yaml_serializer.rb
    man/bundle-platform.1
    man/bundle-update.1
    man/bundle-init.1.txt
    man/bundle-info.ronn
    man/bundle-gem.ronn
    man/bundle-add.1.txt
    man/bundle-list.ronn
    man/bundle-info.1
    man/bundle-init.1
    man/bundle-outdated.ronn
    man/bundle-init.ronn
    man/bundle.1
    man/bundle-show.1.txt
    man/bundle-exec.1
    man/bundle-install.1.txt
    man/bundle-binstubs.1.txt
    man/bundle-open.1.txt
    man/index.txt
    man/bundle-pristine.ronn
    man/bundle-install.1
    man/bundle-inject.ronn
    man/bundle-list.1
    man/bundle-outdated.1.txt
    man/bundle-list.1.txt
    man/bundle-update.ronn
    man/bundle-clean.1.txt
    man/bundle-show.ronn
    man/bundle-pristine.1.txt
    man/bundle-outdated.1
    man/bundle-check.1
    man/bundle-show.1
    man/gemfile.5
    man/bundle-gem.1
    man/bundle-install.ronn
    man/bundle-gem.1.txt
    man/bundle-open.1
    man/bundle-add.ronn
    man/bundle-lock.1.txt
    man/bundle-open.ronn
    man/bundle-lock.1
    man/bundle-exec.ronn
    man/bundle-check.ronn
    man/bundle-info.1.txt
    man/bundle-lock.ronn
    man/bundle-pristine.1
    man/bundle-viz.1.txt
    man/bundle.ronn
    man/bundle-platform.ronn
    man/bundle-binstubs.ronn
    man/bundle-exec.1.txt
    man/bundle.1.txt
    man/bundle-config.1.txt
    man/bundle-package.1.txt
    man/bundle-platform.1.txt
    man/bundle-binstubs.1
    man/bundle-viz.1
    man/bundle-clean.ronn
    man/bundle-package.1
    man/bundle-add.1
    man/bundle-config.1
    man/bundle-package.ronn
    man/bundle-viz.ronn
    man/bundle-check.1.txt
    man/bundle-clean.1
    man/gemfile.5.txt
    man/bundle-inject.1
    man/gemfile.5.ronn
    man/bundle-config.ronn
    man/bundle-inject.1.txt
    man/bundle-update.1.txt
    CHANGELOG.md
    LICENSE.md
    README.md
  ]

  s.bindir        = "exe"
  s.executables   = %w[bundle bundler]
  s.require_paths = ["lib"]
end
