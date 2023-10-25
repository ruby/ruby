# frozen_string_literal: true

require_relative "helpers/compact_index"

class CompactIndexRedirect < CompactIndexAPI
  get "/fetch/actual/gem/:id" do
    redirect "/fetch/actual/gem/#{params[:id]}"
  end

  get "/versions" do
    status 404
  end

  get "/api/v1/dependencies" do
    status 404
  end
end

require_relative "helpers/artifice"

Artifice.activate_with(CompactIndexRedirect)
