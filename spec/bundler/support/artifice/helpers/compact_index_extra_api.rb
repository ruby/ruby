# frozen_string_literal: true

require_relative "compact_index"

class CompactIndexExtraApi < CompactIndexAPI
  get "/extra/names" do
    etag_response do
      CompactIndex.names(gems(gem_repo4).map(&:name))
    end
  end

  get "/extra/versions" do
    etag_response do
      file = tmp("versions.list")
      FileUtils.rm_f(file)
      file = CompactIndex::VersionsFile.new(file.to_s)
      file.create(gems(gem_repo4))
      file.contents
    end
  end

  get "/extra/info/:name" do
    etag_response do
      gem = gems(gem_repo4).find {|g| g.name == params[:name] }
      CompactIndex.info(gem ? gem.versions : [])
    end
  end

  get "/extra/specs.4.8.gz" do
    File.binread("#{gem_repo4}/specs.4.8.gz")
  end

  get "/extra/prerelease_specs.4.8.gz" do
    File.binread("#{gem_repo4}/prerelease_specs.4.8.gz")
  end

  get "/extra/quick/Marshal.4.8/:id" do
    redirect "/extra/fetch/actual/gem/#{params[:id]}"
  end

  get "/extra/fetch/actual/gem/:id" do
    File.binread("#{gem_repo4}/quick/Marshal.4.8/#{params[:id]}")
  end

  get "/extra/gems/:id" do
    File.binread("#{gem_repo4}/gems/#{params[:id]}")
  end
end
