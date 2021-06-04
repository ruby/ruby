# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexExtra < CompactIndexAPI
  get "/extra/versions" do
    halt 404
  end

  get "/extra/api/v1/dependencies" do
    halt 404
  end

  get "/extra/specs.4.8.gz" do
    File.binread("#{gem_repo2}/specs.4.8.gz")
  end

  get "/extra/prerelease_specs.4.8.gz" do
    File.binread("#{gem_repo2}/prerelease_specs.4.8.gz")
  end

  get "/extra/quick/Marshal.4.8/:id" do
    redirect "/extra/fetch/actual/gem/#{params[:id]}"
  end

  get "/extra/fetch/actual/gem/:id" do
    File.binread("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/extra/gems/:id" do
    File.binread("#{gem_repo2}/gems/#{params[:id]}")
  end
end

Artifice.activate_with(CompactIndexExtra)
