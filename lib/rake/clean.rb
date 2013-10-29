# The 'rake/clean' file defines two file lists (CLEAN and CLOBBER) and
# two rake tasks (:clean and :clobber).
#
# [:clean] Clean up the project by deleting scratch files and backup
#          files.  Add files to the CLEAN file list to have the :clean
#          target handle them.
#
# [:clobber] Clobber all generated and non-source files in a project.
#            The task depends on :clean, so all the clean files will
#            be deleted as well as files in the CLOBBER file list.
#            The intent of this task is to return a project to its
#            pristine, just unpacked state.

require 'rake'

# :stopdoc:

module Rake
  module Cleaner
    extend FileUtils

    module_function

    def cleanup_files(file_names)
      file_names.each do |file_name|
        cleanup(file_name)
      end
    end

    def cleanup(file_name, opts={})
      begin
        rm_r file_name, opts
      rescue StandardError => ex
        puts "Failed to remove #{file_name}: #{ex}"
      end
    end
  end
end

CLEAN = ::Rake::FileList["**/*~", "**/*.bak", "**/core"]
CLEAN.clear_exclude.exclude { |fn|
  fn.pathmap("%f").downcase == 'core' && File.directory?(fn)
}

desc "Remove any temporary products."
task :clean do
  Rake::Cleaner.cleanup_files(CLEAN)
end

CLOBBER = ::Rake::FileList.new

desc "Remove any generated file."
task :clobber => [:clean] do
  Rake::Cleaner.cleanup_files(CLOBBER)
end
