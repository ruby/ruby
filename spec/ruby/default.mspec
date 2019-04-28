# Configuration file for Ruby >= 2.0 implementations.

class MSpecScript
  # Language features specs
  set :language, [ 'language' ]

  # Core library specs
  set :core, [ 'core' ]

  # Standard library specs
  set :library, [ 'library' ]

  # Command line specs
  set :command_line, [ 'command_line' ]

  # Security specs
  set :security, [ 'security' ]

  # C extension API specs
  set :capi, [ 'optional/capi' ]

  # A list of _all_ optional specs
  set :optional, get(:capi)

  # An ordered list of the directories containing specs to run
  set :files, get(:command_line) + get(:language) + get(:core) + get(:library) + get(:security) + get(:optional)

  # This set of files is run by mspec ci
  set :ci_files, get(:files)

  # The default implementation to run the specs.
  set :target, 'ruby'

  set :backtrace_filter, /mspec\//

  set :tags_patterns, [
                        [%r(language/),     'tags/language/'],
                        [%r(core/),         'tags/core/'],
                        [%r(command_line/), 'tags/command_line/'],
                        [%r(library/),      'tags/library/'],
                        [%r(security/),     'tags/security/'],
                        [/_spec\.rb$/,      '_tags.txt']
                      ]

  set :toplevel_constants_excludes, [
    /\wSpecs?$/,
    /^CS_CONST/,
  ]
end
