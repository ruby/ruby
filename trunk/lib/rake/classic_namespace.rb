# The following classes used to be in the top level namespace.
# Loading this file enables compatibility with older Rakefile that
# referenced Task from the top level.

Task = Rake::Task
FileTask = Rake::FileTask
FileCreationTask = Rake::FileCreationTask
RakeApp = Rake::Application
