Rails.application.routes.draw do
  constraints -> { Rails.application.config.non_production } do
    namespace :foo do
      resource :bar
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end
  constraints -> { Rails.application.config.non_production } do
    namespace :bar do
      resource :baz
    end
  end

  namespace :admin do
    resource :session

  match "/foobar(*path)", via: :all, to: redirect { |_params, req|
    uri = URI(req.path.gsub("foobar", "foobaz"))
    uri.query = req.query_string.presence
    uri.to_s
  }
end
