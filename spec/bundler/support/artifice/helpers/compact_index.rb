# frozen_string_literal: true

require_relative "endpoint"

$LOAD_PATH.unshift Dir[Spec::Path.base_system_gem_path.join("gems/compact_index*/lib")].first.to_s
require "compact_index"
require "digest"

class CompactIndexAPI < Endpoint
  helpers do
    include Spec::Path

    def load_spec(name, version, platform, gem_repo)
      full_name = "#{name}-#{version}"
      full_name += "-#{platform}" if platform != "ruby"
      Marshal.load(Bundler.rubygems.inflate(File.binread(gem_repo.join("quick/Marshal.4.8/#{full_name}.gemspec.rz"))))
    end

    def etag_response
      response_body = yield
      etag = Digest::MD5.hexdigest(response_body)
      headers "ETag" => quote(etag)
      return if not_modified?(etag)
      headers "Repr-Digest" => "sha-256=:#{Digest::SHA256.base64digest(response_body)}:"
      headers "Surrogate-Control" => "max-age=2592000, stale-while-revalidate=60"
      content_type "text/plain"
      requested_range_for(response_body)
    rescue StandardError => e
      puts e
      puts e.backtrace
      raise
    end

    def not_modified?(etag)
      etags = parse_etags(request.env["HTTP_IF_NONE_MATCH"])

      return unless etags.include?(etag)
      status 304
      body ""
    end

    def requested_range_for(response_body)
      ranges = Rack::Utils.byte_ranges(env, response_body.bytesize)

      if ranges
        status 206
        body ranges.map! {|range| slice_body(response_body, range) }.join
      else
        status 200
        body response_body
      end
    end

    def quote(string)
      %("#{string}")
    end

    def parse_etags(value)
      value ? value.split(/, ?/).select {|s| s.sub!(/"(.*)"/, '\1') } : []
    end

    def slice_body(body, range)
      body.byteslice(range)
    end

    def gems(gem_repo = default_gem_repo)
      @gems ||= {}
      @gems[gem_repo] ||= begin
        specs = Bundler::Deprecate.skip_during do
          %w[specs.4.8 prerelease_specs.4.8].map do |filename|
            Marshal.load(File.open(gem_repo.join(filename)).read).map do |name, version, platform|
              load_spec(name, version, platform, gem_repo)
            end
          end.flatten
        end

        specs.group_by(&:name).map do |name, versions|
          gem_versions = versions.map do |spec|
            deps = spec.runtime_dependencies.map do |d|
              reqs = d.requirement.requirements.map {|r| r.join(" ") }.join(", ")
              CompactIndex::Dependency.new(d.name, reqs)
            end
            begin
              checksum = ENV.fetch("BUNDLER_SPEC_#{name.upcase}_CHECKSUM") do
                Digest(:SHA256).file("#{gem_repo}/gems/#{spec.original_name}.gem").hexdigest
              end
            rescue StandardError
              checksum = nil
            end
            CompactIndex::GemVersion.new(spec.version.version, spec.platform.to_s, checksum, nil,
              deps, spec.required_ruby_version.to_s, spec.required_rubygems_version.to_s)
          end
          CompactIndex::Gem.new(name, gem_versions)
        end
      end
    end
  end

  get "/names" do
    etag_response do
      CompactIndex.names(gems.map(&:name))
    end
  end

  get "/versions" do
    etag_response do
      file = tmp("versions.list")
      FileUtils.rm_f(file)
      file = CompactIndex::VersionsFile.new(file.to_s)
      file.create(gems)
      file.contents
    end
  end

  get "/info/:name" do
    etag_response do
      gem = gems.find {|g| g.name == params[:name] }
      CompactIndex.info(gem ? gem.versions : [])
    end
  end
end
