# frozen_string_literal: true

require_relative "helper"

require "rubygems/remote_fetcher"
require "rubygems/package"

class TestGemRemoteFetcherS3 < Gem::TestCase
  include Gem::DefaultUserInteraction

  def setup
    super

    @a1, @a1_gem = util_gem "a", "1" do |s|
      s.executables << "a_bin"
    end

    @a1.loaded_from = File.join(@gemhome, "specifications", @a1.full_name)
  end

  def assert_fetch_s3(url, signature, token=nil, region="us-east-1", instance_profile_json=nil, method="GET")
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher
    $fetched_uri = nil
    $instance_profile = instance_profile_json

    def fetcher.request(uri, request_class, last_modified = nil)
      $fetched_uri = uri
      res = Gem::Net::HTTPOK.new nil, 200, nil
      def res.body
        "success"
      end
      res
    end

    def fetcher.s3_uri_signer(uri, method)
      require "json"
      s3_uri_signer = Gem::S3URISigner.new(uri, method)
      def s3_uri_signer.ec2_metadata_credentials_json
        JSON.parse($instance_profile)
      end
      # Running sign operation to make sure uri.query is not mutated
      s3_uri_signer.sign
      raise "URI query is not empty: #{uri.query}" unless uri.query.nil?
      s3_uri_signer
    end

    res = fetcher.fetch_s3 Gem::URI.parse(url), nil, (method == "HEAD")

    assert_equal "https://my-bucket.s3.#{region}.amazonaws.com/gems/specs.4.8.gz?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=testuser%2F20190624%2F#{region}%2Fs3%2Faws4_request&X-Amz-Date=20190624T051941Z&X-Amz-Expires=86400#{token ? "&X-Amz-Security-Token=" + token : ""}&X-Amz-SignedHeaders=host&X-Amz-Signature=#{signature}", $fetched_uri.to_s
    if method == "HEAD"
      assert_equal 200, res.code
    else
      assert_equal "success", res
    end
  ensure
    $fetched_uri = nil
  end

  def test_fetch_s3_config_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_head_request
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      token = nil
      region = "us-east-1"
      instance_profile_json = nil
      method = "HEAD"
      assert_fetch_s3 url, "a3c6cf9a2db62e85f4e57f8fc8ac8b5ff5c1fdd4aeef55935d05e05174d9c885", token, region, instance_profile_json, method
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_config_creds_with_region
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass", region: "us-west-2" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716", nil, "us-west-2"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_config_creds_with_token
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass", security_token: "testtoken" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625", "testtoken"
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = nil
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "env" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds_with_region
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = nil
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "env", region: "us-west-2" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716", nil, "us-west-2"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_env_creds_with_token
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = "testtoken"
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "env" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625", "testtoken"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_url_creds
    url = "s3://testuser:testpass@my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
    end
  end

  def test_fetch_s3_instance_profile_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c", nil, "us-east-1",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_instance_profile_creds_with_region
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile", region: "us-west-2" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716", nil, "us-west-2",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_instance_profile_creds_with_token
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625", "testtoken", "us-east-1",
                      '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass", "Token": "testtoken"}'
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def refute_fetch_s3(url, expected_message)
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_s3 Gem::URI.parse(url)
    end

    assert_match expected_message, e.message
  end

  def test_fetch_s3_no_source_key
    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "no s3_source key exists in .gemrc"
  end

  def test_fetch_s3_no_host
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }

    url = "s3://other-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "no key for host other-bucket in s3_source in .gemrc"
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_id
    Gem.configuration[:s3_source] = { "my-bucket" => { secret: "testpass" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "s3_source for my-bucket missing id or secret"
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_secret
    Gem.configuration[:s3_source] = { "my-bucket" => { id: "testuser" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3 url, "s3_source for my-bucket missing id or secret"
  ensure
    Gem.configuration[:s3_source] = nil
  end
end
