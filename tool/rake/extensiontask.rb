module Rake
  class ExtensionTask < TaskLib
    def initialize(...)
      task :compile do
        puts "Dummy `compile` task defined in #{__FILE__}"
      end
    end
  end
end
