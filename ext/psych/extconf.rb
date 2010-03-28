require 'mkmf'

# :stopdoc:

RbConfig::MAKEFILE_CONFIG['CC'] = ENV['CC'] if ENV['CC']

INCLUDEDIR = Config::CONFIG['includedir']
LIBDIR     = Config::CONFIG['libdir']
LIB_DIRS   = ['/opt/local/lib', '/usr/local/lib', LIBDIR, '/usr/lib']
libyaml    = dir_config 'libyaml', '/opt/local/include', '/opt/local/lib'

def asplode missing
  abort "#{missing} is missing. Try 'port install libyaml +universal' " +
        "or 'yum install libyaml-devel'"
end

asplode('yaml.h')  unless find_header  'yaml.h'
asplode('libyaml') unless find_library 'yaml', 'yaml_get_version'

create_makefile 'psych/psych'

# :startdoc:
