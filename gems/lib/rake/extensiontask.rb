require "rake/tasklib" unless defined?(Rake::TaskLib)

module Rake
  class ExtensionTask < TaskLib
    def initialize(...)
      task :compile do |args|
        puts "Dummy `compile` task defined in #{__FILE__}"
        puts "#{args.name} => #{args.prereqs.join(' ')}"
      end
    end
  end
end
