# frozen_string_literal: true

require_relative "openssl"
require_relative "user_interaction"

##
# S3URISigner implements AWS SigV4 for S3 Source to avoid a dependency on the aws-sdk-* gems
# More on AWS SigV4: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
class Gem::S3URISigner
  include Gem::UserInteraction

  class ConfigurationError < Gem::Exception
    def initialize(message)
      super message
    end

    def to_s # :nodoc:
      super.to_s
    end
  end

  class InstanceProfileError < Gem::Exception
    def initialize(message)
      super message
    end

    def to_s # :nodoc:
      super.to_s
    end
  end

  attr_accessor :uri
  attr_accessor :method

  def initialize(uri, method)
    @uri = uri
    @method = method
  end

  ##
  # Signs S3 URI using query-params according to the reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
  def sign(expiration = 86_400)
    s3_config = fetch_s3_config

    current_time = Time.now.utc
    date_time = current_time.strftime("%Y%m%dT%H%M%SZ")
    date = date_time[0,8]

    credential_info = "#{date}/#{s3_config.region}/s3/aws4_request"
    canonical_host = "#{uri.host}.s3.#{s3_config.region}.amazonaws.com"

    query_params = generate_canonical_query_params(s3_config, date_time, credential_info, expiration)
    canonical_request = generate_canonical_request(canonical_host, query_params)
    string_to_sign = generate_string_to_sign(date_time, credential_info, canonical_request)
    signature = generate_signature(s3_config, date, string_to_sign)

    Gem::URI.parse("https://#{canonical_host}#{uri.path}?#{query_params}&X-Amz-Signature=#{signature}")
  end

  private

  S3Config = Struct.new :access_key_id, :secret_access_key, :security_token, :region

  def generate_canonical_query_params(s3_config, date_time, credential_info, expiration)
    canonical_params = {}
    canonical_params["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256"
    canonical_params["X-Amz-Credential"] = "#{s3_config.access_key_id}/#{credential_info}"
    canonical_params["X-Amz-Date"] = date_time
    canonical_params["X-Amz-Expires"] = expiration.to_s
    canonical_params["X-Amz-SignedHeaders"] = "host"
    canonical_params["X-Amz-Security-Token"] = s3_config.security_token if s3_config.security_token

    # Sorting is required to generate proper signature
    canonical_params.sort.to_h.map do |key, value|
      "#{base64_uri_escape(key)}=#{base64_uri_escape(value)}"
    end.join("&")
  end

  def generate_canonical_request(canonical_host, query_params)
    [
      method.upcase,
      uri.path,
      query_params,
      "host:#{canonical_host}",
      "", # empty params
      "host",
      "UNSIGNED-PAYLOAD",
    ].join("\n")
  end

  def generate_string_to_sign(date_time, credential_info, canonical_request)
    [
      "AWS4-HMAC-SHA256",
      date_time,
      credential_info,
      OpenSSL::Digest::SHA256.hexdigest(canonical_request),
    ].join("\n")
  end

  def generate_signature(s3_config, date, string_to_sign)
    date_key = OpenSSL::HMAC.digest("sha256", "AWS4" + s3_config.secret_access_key, date)
    date_region_key = OpenSSL::HMAC.digest("sha256", date_key, s3_config.region)
    date_region_service_key = OpenSSL::HMAC.digest("sha256", date_region_key, "s3")
    signing_key = OpenSSL::HMAC.digest("sha256", date_region_service_key, "aws4_request")
    OpenSSL::HMAC.hexdigest("sha256", signing_key, string_to_sign)
  end

  ##
  # Extracts S3 configuration for S3 bucket
  def fetch_s3_config
    return S3Config.new(uri.user, uri.password, nil, "us-east-1") if uri.user && uri.password

    s3_source = Gem.configuration[:s3_source] || Gem.configuration["s3_source"]
    host = uri.host
    raise ConfigurationError.new("no s3_source key exists in .gemrc") unless s3_source

    auth = s3_source[host] || s3_source[host.to_sym]
    raise ConfigurationError.new("no key for host #{host} in s3_source in .gemrc") unless auth

    provider = auth[:provider] || auth["provider"]
    case provider
    when "env"
      id = ENV["AWS_ACCESS_KEY_ID"]
      secret = ENV["AWS_SECRET_ACCESS_KEY"]
      security_token = ENV["AWS_SESSION_TOKEN"]
    when "instance_profile"
      credentials = ec2_metadata_credentials_json
      id = credentials["AccessKeyId"]
      secret = credentials["SecretAccessKey"]
      security_token = credentials["Token"]
    else
      id = auth[:id] || auth["id"]
      secret = auth[:secret] || auth["secret"]
      security_token = auth[:security_token] || auth["security_token"]
    end

    raise ConfigurationError.new("s3_source for #{host} missing id or secret") unless id && secret

    region = auth[:region] || auth["region"] || "us-east-1"
    S3Config.new(id, secret, security_token, region)
  end

  def base64_uri_escape(str)
    str.gsub(%r{[\+/=\n]}, BASE64_URI_TRANSLATE)
  end

  def ec2_metadata_credentials_json
    require_relative "vendored_net_http"
    require_relative "request"
    require_relative "request/connection_pools"
    require "json"

    # First try V2 fallback to V1
    res = nil
    begin
      res = ec2_metadata_credentials_imds_v2
    rescue InstanceProfileError
      alert_warning "Unable to access ec2 credentials via IMDSv2, falling back to IMDSv1"
      res = ec2_metadata_credentials_imds_v1
    end
    res
  end

  def ec2_metadata_credentials_imds_v2
    token = ec2_metadata_token
    iam_info = ec2_metadata_request(EC2_IAM_INFO, token:)
    # Expected format: arn:aws:iam::<id>:instance-profile/<role_name>
    role_name = iam_info["InstanceProfileArn"].split("/").last
    ec2_metadata_request(EC2_IAM_SECURITY_CREDENTIALS + role_name, token:)
  end

  def ec2_metadata_credentials_imds_v1
    iam_info = ec2_metadata_request(EC2_IAM_INFO, token: nil)
    # Expected format: arn:aws:iam::<id>:instance-profile/<role_name>
    role_name = iam_info["InstanceProfileArn"].split("/").last
    ec2_metadata_request(EC2_IAM_SECURITY_CREDENTIALS + role_name, token: nil)
  end

  def ec2_metadata_request(url, token:)
    request = ec2_iam_request(Gem::URI(url), Gem::Net::HTTP::Get)

    response = request.fetch do |req|
      if token
        req.add_field "X-aws-ec2-metadata-token", token
      end
    end

    case response
    when Gem::Net::HTTPOK then
      JSON.parse(response.body)
    else
      raise InstanceProfileError.new("Unable to fetch AWS metadata from #{uri}: #{response.message} #{response.code}")
    end
  end

  def ec2_metadata_token
    request = ec2_iam_request(Gem::URI(EC2_IAM_TOKEN), Gem::Net::HTTP::Put)

    response = request.fetch do |req|
      req.add_field "X-aws-ec2-metadata-token-ttl-seconds", 60
    end

    case response
    when Gem::Net::HTTPOK then
      response.body
    else
      raise InstanceProfileError.new("Unable to fetch AWS metadata from #{uri}: #{response.message} #{response.code}")
    end
  end

  def ec2_iam_request(uri, verb)
    @request_pool ||= create_request_pool(uri)
    Gem::Request.new(uri, verb, nil, @request_pool)
  end

  def create_request_pool(uri)
    proxy_uri = Gem::Request.proxy_uri(Gem::Request.get_proxy_from_env(uri.scheme))
    certs = Gem::Request.get_cert_files
    Gem::Request::ConnectionPools.new(proxy_uri, certs).pool_for(uri)
  end

  BASE64_URI_TRANSLATE = { "+" => "%2B", "/" => "%2F", "=" => "%3D", "\n" => "" }.freeze
  EC2_IAM_TOKEN = "http://169.254.169.254/latest/api/token"
  EC2_IAM_INFO = "http://169.254.169.254/latest/meta-data/iam/info"
  EC2_IAM_SECURITY_CREDENTIALS = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
end
