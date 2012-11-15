require 'rake/application'

module Rake

  # Rake module singleton methods.
  #
  class << self
    # Current Rake Application
    def application
      @application ||= Rake::Application.new
    end

    # Set the current Rake application object.
    def application=(app)
      @application = app
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
      files.each do |file|
        application.options.rakelib << file
      end
    end

    # Get a sorted list of files matching the pattern. This method
    # should be prefered to Dir[pattern] and Dir.glob[pattern] because
    # the files returned are guaranteed to be sorted.
    def glob(pattern, *args)
      Dir.glob(pattern, *args).sort
    end
  end

end
