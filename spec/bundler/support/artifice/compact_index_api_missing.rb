# frozen_string_literal: true

require File.expand_path("../compact_index", __FILE__)

Artifice.deactivate

class CompactIndexApiMissing < CompactIndexAPI
  get "/fetch/actual/gem/:id" do
    $stderr.puts params[:id]
    if params[:id] == "rack-1.0.gemspec.rz"
      halt 404
    else
      File.read("#{gem_repo2}/quick/Marshal.4.8/#{params[:id]}")
    end
  end
end

Artifice.activate_with(CompactIndexApiMissing)
