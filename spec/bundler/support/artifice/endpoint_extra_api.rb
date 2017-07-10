# frozen_string_literal: true
require File.expand_path("../endpoint", __FILE__)

Artifice.deactivate

class EndpointExtraApi < Endpoint
  get "/extra/api/v1/dependencies" do
    deps = dependencies_for(params[:gems], gem_repo4)
    Marshal.dump(deps)
  end

  get "/extra/specs.4.8.gz" do
    File.read("#{gem_repo4}/specs.4.8.gz")
  end

  get "/extra/prerelease_specs.4.8.gz" do
    File.read("#{gem_repo4}/prerelease_specs.4.8.gz")
  end

  get "/extra/quick/Marshal.4.8/:id" do
    redirect "/extra/fetch/actual/gem/#{params[:id]}"
  end

  get "/extra/fetch/actual/gem/:id" do
    File.read("#{gem_repo4}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/extra/gems/:id" do
    File.read("#{gem_repo4}/gems/#{params[:id]}")
  end
end

Artifice.activate_with(EndpointExtraApi)
