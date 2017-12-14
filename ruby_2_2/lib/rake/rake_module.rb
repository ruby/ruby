require 'rake/application'

module Rake

  class << self
    # Current Rake Application
    def application
      @application ||= Rake::Application.new
    end

    # Set the current Rake application object.
    def application=(app)
      @application = app
    end

    def suggested_thread_count # :nodoc:
      @cpu_count ||= Rake::CpuCounter.count
      @cpu_count + 4
    end

    # Return the original directory where the Rake application was started.
    def original_dir
      application.original_dir
    end

    # Load a rakefile.
    def load_rakefile(path)
      load(path)
    end

    # Add files to the rakelib list
    def add_rakelib(*files)
      application.options.rakelib ||= []
      application.options.rakelib.concat(files)
    end
  end

end
