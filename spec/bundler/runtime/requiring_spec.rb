# frozen_string_literal: true

RSpec.describe "Requiring bundler" do
  it "takes care of requiring rubygems when entrypoint is bundler/setup" do
    sys_exec("#{Gem.ruby} -I#{lib_dir} -rbundler/setup -e'puts true'", :env => { "RUBYOPT" => opt_add("--disable=gems", ENV["RUBYOPT"]) })

    expect(last_command.stdboth).to eq("true")
  end

  it "takes care of requiring rubygems when requiring just bundler" do
    sys_exec("#{Gem.ruby} -I#{lib_dir} -rbundler -e'puts true'", :env => { "RUBYOPT" => opt_add("--disable=gems", ENV["RUBYOPT"]) })

    expect(last_command.stdboth).to eq("true")
  end
end
