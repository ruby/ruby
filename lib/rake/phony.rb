# Defines a :phony task that you can use as a dependency. This allows
# file-based tasks to use non-file-based tasks as prerequisites
# without forcing them to rebuild.
#
# See FileTask#out_of_date? and Task#timestamp for more info.

require 'rake'

task :phony

def (Rake::Task[:phony]).timestamp
  Time.at 0
end
