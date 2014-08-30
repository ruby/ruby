module SimpleCov
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load 'simplecov/railties/tasks.rake'
    end
  end
end
