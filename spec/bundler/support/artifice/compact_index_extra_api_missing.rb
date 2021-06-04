# frozen_string_literal: true

require_relative "compact_index_extra_api"

Artifice.deactivate

class CompactIndexExtraAPIMissing < CompactIndexExtraApi
  get "/extra/fetch/actual/gem/:id" do
    if params[:id] == "missing-1.0.gemspec.rz"
      halt 404
    else
      File.binread("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
    end
  end
end

Artifice.activate_with(CompactIndexExtraAPIMissing)
