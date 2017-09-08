# frozen_string_literal: true
# Vlad task for Bundler.
#
# Add "require 'bundler/vlad'" in your Vlad deploy.rb, and
# include the vlad:bundle:install task in your vlad:deploy task.
require "bundler/deployment"

include Rake::DSL if defined? Rake::DSL

namespace :vlad do
  Bundler::Deployment.define_task(Rake::RemoteTask, :remote_task, :roles => :app)
end
