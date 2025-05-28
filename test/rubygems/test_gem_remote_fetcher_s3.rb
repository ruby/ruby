# frozen_string_literal: true

require_relative "helper"

require "rubygems/remote_fetcher"
require "rubygems/package"

class TestGemRemoteFetcherS3 < Gem::TestCase
  include Gem::DefaultUserInteraction

  class FakeGemRequest < Gem::Request

    attr_reader :last_request, :uri

    # Override perform_request to stub things
    def perform_request(request)
      @last_request = request
      @response
    end

    def set_response(response)
      @response = response
    end
  end

  class FakeS3URISigner < Gem::S3URISigner
    # Convenience method to output the recent aws iam queries made in tests
    # this outputs the verb, path, and any non-generic headers
    def recent_aws_query_logs
      sreqs = @aws_iam_calls.map do |c|
        r = c.last_request
        s = +"#{r.method} #{c.uri}\n"
        r.each_header do |key, v|
          # Only include headers that start with x-
          next unless key.start_with?("x-")
          s << "    #{key}=#{v}\n"
        end
        s
      end

      sreqs.join("")
    end

    def initialize(uri, method)
      @aws_iam_calls = []
      super
    end

    def ec2_iam_request(uri, verb)
      fake_s3_request = FakeGemRequest.new(uri, verb, nil, nil)
      @aws_iam_calls << fake_s3_request

      case uri.to_s
      when "http://169.254.169.254/latest/api/token"
        res = Gem::Net::HTTPOK.new nil, 200, nil
        def res.body
          "mysecrettoken"
        end
        fake_s3_request.set_response(res)

      when "http://169.254.169.254/latest/meta-data/iam/info"
        res = Gem::Net::HTTPOK.new nil, 200, nil
        def res.body
          <<~JSON
            {
              "Code": "Success",
              "LastUpdated": "2023-05-27:05:05",
              "InstanceProfileArn": "arn:aws:iam::somesecretid:instance-profile/TestRole",
              "InstanceProfileId": "SOMEPROFILEID"
            }
          JSON
        end
        fake_s3_request.set_response(res)

      when "http://169.254.169.254/latest/meta-data/iam/security-credentials/TestRole"
        res = Gem::Net::HTTPOK.new nil, 200, nil
        def res.body
          $instance_profile
        end
        fake_s3_request.set_response(res)

      else
        raise "Unexpected request to #{uri}"
      end

      fake_s3_request
    end
  end

  class FakeGemFetcher < Gem::RemoteFetcher

    attr_reader :fetched_uri, :last_s3_uri_signer

    def request(uri, request_class, last_modified = nil)
      @fetched_uri = uri
      res = Gem::Net::HTTPOK.new nil, 200, nil
      def res.body
        "success"
      end
      res
    end

    def s3_uri_signer(uri, method)
      @last_s3_uri_signer = FakeS3URISigner.new(uri, method)
    end
  end

  def setup
    super

    @a1, @a1_gem = util_gem "a", "1" do |s|
      s.executables << "a_bin"
    end

    @a1.loaded_from = File.join(@gemhome, "specifications", @a1.full_name)
  end

  def assert_fetched_s3_with_imds_v2
    # Three API requests:
    # 1. Get the token
    # 2. Lookup profile details
    # 3. Query the credentials
    expected = <<~TEXT
      PUT http://169.254.169.254/latest/api/token
          x-aws-ec2-metadata-token-ttl-seconds=60
      GET http://169.254.169.254/latest/meta-data/iam/info
          x-aws-ec2-metadata-token=mysecrettoken
      GET http://169.254.169.254/latest/meta-data/iam/security-credentials/TestRole
          x-aws-ec2-metadata-token=mysecrettoken
    TEXT
    recent_aws_query_logs = @fetcher.last_s3_uri_signer.recent_aws_query_logs
    assert_equal(expected.strip, recent_aws_query_logs.strip)
  end

  def assert_fetch_s3(url:, signature:, token: nil, region: "us-east-1", instance_profile_json: nil, method: "GET")
    @fetcher = FakeGemFetcher.new nil
    $instance_profile = instance_profile_json
    res = fetcher.fetch_s3 Gem::URI.parse(url), nil, (method == "HEAD")

    assert_equal "https://my-bucket.s3.#{region}.amazonaws.com/gems/specs.4.8.gz?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=testuser%2F20190624%2F#{region}%2Fs3%2Faws4_request&X-Amz-Date=20190624T051941Z&X-Amz-Expires=86400#{token ? "&X-Amz-Security-Token=" + token : ""}&X-Amz-SignedHeaders=host&X-Amz-Signature=#{signature}", @fetcher.fetched_uri.to_s
    if method == "HEAD"
      assert_equal 200, res.code
    else
      assert_equal "success", res
    end

    # Validation for EC2 IAM signing
    if Gem.configuration[:s3_source]&.dig("my-bucket", :provider) == "instance_profile"
      # Three API requests:
      # 1. Get the token
      # 2. Lookup profile details
      # 3. Query the credentials
      expected = <<~TEXT
        PUT http://169.254.169.254/latest/api/token
            x-aws-ec2-metadata-token-ttl-seconds=60
        GET http://169.254.169.254/latest/meta-data/iam/info
            x-aws-ec2-metadata-token=mysecrettoken
        GET http://169.254.169.254/latest/meta-data/iam/security-credentials/TestRole
            x-aws-ec2-metadata-token=mysecrettoken
      TEXT
      recent_aws_query_logs = @fetcher.last_s3_uri_signer.recent_aws_query_logs
      assert_equal(expected.strip, recent_aws_query_logs.strip) 
    else
      assert_equal("", @fetcher.last_s3_uri_signer.recent_aws_query_logs)
    end
  ensure
    $instance_profile = nil
  end

  def test_fetch_s3_config_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3(
        url: url,
        signature: "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c", 
      )
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

      assert_fetch_s3(
        url: url,
        signature: "a3c6cf9a2db62e85f4e57f8fc8ac8b5ff5c1fdd4aeef55935d05e05174d9c885", 
        token: token, 
        region: region, 
        instance_profile_json: instance_profile_json,
        method: method
      )
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
      assert_fetch_s3(
        url: url,
        signature: "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716",
        region: "us-west-2"
      )
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
      assert_fetch_s3(
        url: url,
        signature: "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625",
        token: "testtoken"
      )
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
      assert_fetch_s3(
        url: url,
        signature: "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
      )
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
      assert_fetch_s3(
        url: url,
        signature: "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716",
        token: nil,
        region: "us-west-2"
      )
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
      assert_fetch_s3(
        url: url,
        signature: "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625",
        token: "testtoken"
      )
    end
  ensure
    ENV.each_key {|key| ENV.delete(key) if key.start_with?("AWS") }
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_url_creds
    url = "s3://testuser:testpass@my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3(
        url: url,
        signature: "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
      )
    end
  end

  def test_fetch_s3_instance_profile_creds
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3(
        url: url,
        signature: "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c",
        region: "us-east-1",
        instance_profile_json: '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
      )
      assert_fetched_s3_with_imds_v2
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
      assert_fetch_s3(
        url: url,
        signature: "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716",
        region: "us-west-2",
        instance_profile_json: '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass"}'
      )
      assert_fetched_s3_with_imds_v2
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
      assert_fetch_s3(
        url: url,
        signature: "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625",
        token: "testtoken",
        region: "us-east-1",
        instance_profile_json: '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass", "Token": "testtoken"}'
      )
      assert_fetched_s3_with_imds_v2
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_instance_profile_creds_with_fallback
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "instance_profile" },
    }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    Time.stub :now, Time.at(1_561_353_581) do
      assert_fetch_s3(
        url: url,
        signature: "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625",
        token: "testtoken",
        region: "us-east-1",
        instance_profile_json: '{"AccessKeyId": "testuser", "SecretAccessKey": "testpass", "Token": "testtoken"}'
      )
      assert_fetched_s3_with_imds_v2
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def refute_fetch_s3(url:, expected_message:)
    fetcher = Gem::RemoteFetcher.new nil
    @fetcher = fetcher

    e = assert_raise Gem::RemoteFetcher::FetchError do
      fetcher.fetch_s3 Gem::URI.parse(url)
    end

    assert_match expected_message, e.message
  end

  def test_fetch_s3_no_source_key
    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3(url: url, expected_message: "no s3_source key exists in .gemrc")
  end

  def test_fetch_s3_no_host
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }

    url = "s3://other-bucket/gems/specs.4.8.gz"
    refute_fetch_s3(url: url, expected_message: "no key for host other-bucket in s3_source in .gemrc")
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_id
    Gem.configuration[:s3_source] = { "my-bucket" => { secret: "testpass" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3(url: url, expected_message: "s3_source for my-bucket missing id or secret")
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_fetch_s3_no_secret
    Gem.configuration[:s3_source] = { "my-bucket" => { id: "testuser" } }

    url = "s3://my-bucket/gems/specs.4.8.gz"
    refute_fetch_s3(url: url, expected_message: "s3_source for my-bucket missing id or secret")
  ensure
    Gem.configuration[:s3_source] = nil
  end
end
