require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "YAML.dump_stream" do
  it "returns a YAML stream containing the objects passed" do
    YAML.dump_stream('foo', 20, [], {}).should match_yaml("--- foo\n--- 20\n--- []\n\n--- {}\n\n")
  end
end
