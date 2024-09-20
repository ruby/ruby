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

  def assert_fetch_s3(url, signature, token=nil, region="us-east-1", instance_profile_json=nil)
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

    def fetcher.s3_uri_signer(uri)
      require "json"
      s3_uri_signer = Gem::S3URISigner.new(uri)
      def s3_uri_signer.ec2_metadata_credentials_json
        JSON.parse($instance_profile)
      end
      # Running sign operation to make sure uri.query is not mutated
      s3_uri_signer.sign
      raise "URI query is not empty: #{uri.query}" unless uri.query.nil?
      s3_uri_signer
    end

    data = fetcher.fetch_s3 Gem::URI.parse(url)

    assert_equal "https://my-bucket.s3.#{region}.amazonaws.com/gems/specs.4.8.gz?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=testuser%2F20190624%2F#{region}%2Fs3%2Faws4_request&X-Amz-Date=20190624T050641Z&X-Amz-Expires=86400#{token ? "&X-Amz-Security-Token=" + token : ""}&X-Amz-SignedHeaders=host&X-Amz-Signature=#{signature}", $fetched_uri.to_s
    assert_equal "success", data
  ensure
    $fetched_uri = nil
  end

  def test_fetch_s3_config_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
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
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2"
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
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken"
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
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
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
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2"
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
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken"
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_url_creds
    url = "s3://testuser:testpass@my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b"
    end
  end

  def test_fetch_s3_instance_profile_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3 url, "20f974027db2f3cd6193565327a7c73457a138efb1a63ea248d185ce6827d41b", nil, "us-east-1",
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
      assert_fetch_s3 url, "4afc3010757f1fd143e769f1d1dabd406476a4fc7c120e9884fd02acbb8f26c9", nil, "us-west-2",
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
      assert_fetch_s3 url, "935160a427ef97e7630f799232b8f208c4a4e49aad07d0540572a2ad5fe9f93c", "testtoken", "us-east-1",
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
