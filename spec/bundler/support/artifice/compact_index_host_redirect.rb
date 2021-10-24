# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexHostRedirect < CompactIndexAPI
  get "/fetch/actual/gem/:id", :host_name => "localgemserver.test" do
    redirect "http://bundler.localgemserver.test#{request.path_info}"
  end

  get "/versions" do
    status 404
  end

  get "/api/v1/dependencies" do
    status 404
  end
end

Artifice.activate_with(CompactIndexHostRedirect)
