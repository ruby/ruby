# frozen_string_literal: true

require "bundler/mirror"

RSpec.describe Bundler::Settings::Mirror do
  let(:mirror) { Bundler::Settings::Mirror.new }

  it "returns zero when fallback_timeout is not set" do
    expect(mirror.fallback_timeout).to eq(0)
  end

  it "takes a number as a fallback_timeout" do
    mirror.fallback_timeout = 1
    expect(mirror.fallback_timeout).to eq(1)
  end

  it "takes truthy as a default fallback timeout" do
    mirror.fallback_timeout = true
    expect(mirror.fallback_timeout).to eq(0.1)
  end

  it "takes falsey as a zero fallback timeout" do
    mirror.fallback_timeout = false
    expect(mirror.fallback_timeout).to eq(0)
  end

  it "takes a string with 'true' as a default fallback timeout" do
    mirror.fallback_timeout = "true"
    expect(mirror.fallback_timeout).to eq(0.1)
  end

  it "takes a string with 'false' as a zero fallback timeout" do
    mirror.fallback_timeout = "false"
    expect(mirror.fallback_timeout).to eq(0)
  end

  it "takes a string for the uri but returns an uri object" do
    mirror.uri = "http://localhost:9292"
    expect(mirror.uri).to eq(Bundler::URI("http://localhost:9292"))
  end

  it "takes an uri object for the uri" do
    mirror.uri = Bundler::URI("http://localhost:9293")
    expect(mirror.uri).to eq(Bundler::URI("http://localhost:9293"))
  end

  context "without a uri" do
    it "invalidates the mirror" do
      mirror.validate!
      expect(mirror.valid?).to be_falsey
    end
  end

  context "with an uri" do
    before { mirror.uri = "http://localhost:9292" }

    context "without a fallback timeout" do
      it "is not valid by default" do
        expect(mirror.valid?).to be_falsey
      end

      context "when probed" do
        let(:probe) { double }

        context "with a replying mirror" do
          before do
            allow(probe).to receive(:replies?).and_return(true)
            mirror.validate!(probe)
          end

          it "is valid" do
            expect(mirror.valid?).to be_truthy
          end
        end

        context "with a non replying mirror" do
          before do
            allow(probe).to receive(:replies?).and_return(false)
            mirror.validate!(probe)
          end

          it "is still valid" do
            expect(mirror.valid?).to be_truthy
          end
        end
      end
    end

    context "with a fallback timeout" do
      before { mirror.fallback_timeout = 1 }

      it "is not valid by default" do
        expect(mirror.valid?).to be_falsey
      end

      context "when probed" do
        let(:probe) { double }

        context "with a replying mirror" do
          before do
            allow(probe).to receive(:replies?).and_return(true)
            mirror.validate!(probe)
          end

          it "is valid" do
            expect(mirror.valid?).to be_truthy
          end

          it "is validated only once" do
            allow(probe).to receive(:replies?).and_raise("Only once!")
            mirror.validate!(probe)
            expect(mirror.valid?).to be_truthy
          end
        end

        context "with a non replying mirror" do
          before do
            allow(probe).to receive(:replies?).and_return(false)
            mirror.validate!(probe)
          end

          it "is not valid" do
            expect(mirror.valid?).to be_falsey
          end

          it "is validated only once" do
            allow(probe).to receive(:replies?).and_raise("Only once!")
            mirror.validate!(probe)
            expect(mirror.valid?).to be_falsey
          end
        end
      end
    end

    describe "#==" do
      it "returns true if uri and fallback timeout are the same" do
        uri = "https://ruby.taobao.org"
        mirror = Bundler::Settings::Mirror.new(uri, 1)
        another_mirror = Bundler::Settings::Mirror.new(uri, 1)

        expect(mirror == another_mirror).to be true
      end
    end
  end
end

RSpec.describe Bundler::Settings::Mirrors do
  let(:localhost_uri) { Bundler::URI("http://localhost:9292") }

  context "with a just created mirror" do
    let(:mirrors) do
      probe = double
      allow(probe).to receive(:replies?).and_return(true)
      Bundler::Settings::Mirrors.new(probe)
    end

    it "returns a mirror that contains the source uri for an unknown uri" do
      mirror = mirrors.for("http://rubygems.org/")
      expect(mirror).to eq(Bundler::Settings::Mirror.new("http://rubygems.org/"))
    end

    it "parses a mirror key and returns a mirror for the parsed uri" do
      mirrors.parse("mirror.http://rubygems.org/", localhost_uri)
      expect(mirrors.for("http://rubygems.org/").uri).to eq(localhost_uri)
    end

    it "parses a relative mirror key and returns a mirror for the parsed http uri" do
      mirrors.parse("mirror.rubygems.org", localhost_uri)
      expect(mirrors.for("http://rubygems.org/").uri).to eq(localhost_uri)
    end

    it "parses a relative mirror key and returns a mirror for the parsed https uri" do
      mirrors.parse("mirror.rubygems.org", localhost_uri)
      expect(mirrors.for("https://rubygems.org/").uri).to eq(localhost_uri)
    end

    context "with a uri parsed already" do
      before { mirrors.parse("mirror.http://rubygems.org/", localhost_uri) }

      it "takes a mirror fallback_timeout and assigns the timeout" do
        mirrors.parse("mirror.http://rubygems.org.fallback_timeout", "2")
        expect(mirrors.for("http://rubygems.org/").fallback_timeout).to eq(2)
      end

      it "parses a 'true' fallback timeout and sets the default timeout" do
        mirrors.parse("mirror.http://rubygems.org.fallback_timeout", "true")
        expect(mirrors.for("http://rubygems.org/").fallback_timeout).to eq(0.1)
      end

      it "parses a 'false' fallback timeout and sets it to zero" do
        mirrors.parse("mirror.http://rubygems.org.fallback_timeout", "false")
        expect(mirrors.for("http://rubygems.org/").fallback_timeout).to eq(0)
      end
    end
  end

  context "with a mirror prober that replies on time" do
    let(:mirrors) do
      probe = double
      allow(probe).to receive(:replies?).and_return(true)
      Bundler::Settings::Mirrors.new(probe)
    end

    context "with a default fallback_timeout for rubygems.org" do
      before do
        mirrors.parse("mirror.http://rubygems.org/", localhost_uri)
        mirrors.parse("mirror.http://rubygems.org.fallback_timeout", "true")
      end

      it "returns localhost" do
        expect(mirrors.for("http://rubygems.org").uri).to eq(localhost_uri)
      end
    end

    context "with a mirror for all" do
      before do
        mirrors.parse("mirror.all", localhost_uri)
      end

      context "without a fallback timeout" do
        it "returns localhost uri for rubygems" do
          expect(mirrors.for("http://rubygems.org").uri).to eq(localhost_uri)
        end

        it "returns localhost for any other url" do
          expect(mirrors.for("http://whatever.com/").uri).to eq(localhost_uri)
        end
      end
      context "with a fallback timeout" do
        before { mirrors.parse("mirror.all.fallback_timeout", "1") }

        it "returns localhost uri for rubygems" do
          expect(mirrors.for("http://rubygems.org").uri).to eq(localhost_uri)
        end

        it "returns localhost for any other url" do
          expect(mirrors.for("http://whatever.com/").uri).to eq(localhost_uri)
        end
      end
    end
  end

  context "with a mirror prober that does not reply on time" do
    let(:mirrors) do
      probe = double
      allow(probe).to receive(:replies?).and_return(false)
      Bundler::Settings::Mirrors.new(probe)
    end

    context "with a localhost mirror for all" do
      before { mirrors.parse("mirror.all", localhost_uri) }

      context "without a fallback timeout" do
        it "returns localhost" do
          expect(mirrors.for("http://whatever.com").uri).to eq(localhost_uri)
        end
      end

      context "with a fallback timeout" do
        before { mirrors.parse("mirror.all.fallback_timeout", "true") }

        it "returns the source uri, not localhost" do
          expect(mirrors.for("http://whatever.com").uri).to eq(Bundler::URI("http://whatever.com/"))
        end
      end
    end

    context "with localhost as a mirror for rubygems.org" do
      before { mirrors.parse("mirror.http://rubygems.org/", localhost_uri) }

      context "without a fallback timeout" do
        it "returns the uri that is not mirrored" do
          expect(mirrors.for("http://whatever.com").uri).to eq(Bundler::URI("http://whatever.com/"))
        end

        it "returns localhost for rubygems.org" do
          expect(mirrors.for("http://rubygems.org/").uri).to eq(localhost_uri)
        end
      end

      context "with a fallback timeout" do
        before { mirrors.parse("mirror.http://rubygems.org/.fallback_timeout", "true") }

        it "returns the uri that is not mirrored" do
          expect(mirrors.for("http://whatever.com").uri).to eq(Bundler::URI("http://whatever.com/"))
        end

        it "returns rubygems.org for rubygems.org" do
          expect(mirrors.for("http://rubygems.org/").uri).to eq(Bundler::URI("http://rubygems.org/"))
        end
      end
    end
  end
end

RSpec.describe Bundler::Settings::TCPSocketProbe do
  let(:probe) { Bundler::Settings::TCPSocketProbe.new }

  context "with a listening TCP Server" do
    def with_server_and_mirror
      server = TCPServer.new("0.0.0.0", 0)
      mirror = Bundler::Settings::Mirror.new("http://0.0.0.0:#{server.addr[1]}", 1)
      yield server, mirror
      server.close unless server.closed?
    end

    it "probes the server correctly" do
      skip "obscure error" if Gem.win_platform?

      with_server_and_mirror do |server, mirror|
        expect(server.closed?).to be_falsey
        expect(probe.replies?(mirror)).to be_truthy
      end
    end

    it "probes falsey when the server is down" do
      with_server_and_mirror do |server, mirror|
        server.close
        expect(probe.replies?(mirror)).to be_falsey
      end
    end
  end

  context "with an invalid mirror" do
    let(:mirror) { Bundler::Settings::Mirror.new("http://127.0.0.127:9292", true) }

    it "fails with a timeout when there is nothing to tcp handshake" do
      expect(probe.replies?(mirror)).to be_falsey
    end
  end
end
