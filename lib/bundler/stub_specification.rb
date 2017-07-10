# frozen_string_literal: true
require "bundler/remote_specification"

module Bundler
  class StubSpecification < RemoteSpecification
    def self.from_stub(stub)
      spec = new(stub.name, stub.version, stub.platform, nil)
      spec.stub = stub
      spec
    end

    attr_accessor :stub

    def to_yaml
      _remote_specification.to_yaml
    end

  private

    def _remote_specification
      stub.to_spec
    end
  end
end
