require_relative '../../spec_helper'
require_relative 'spec_helper'

describe "Net::FTP#initialize" do
  before :each do
    @ftp = Net::FTP.allocate
    @ftp.stub!(:connect)
    @port_args = []
    @port_args << 21
  end

  it "is private" do
    Net::FTP.should have_private_instance_method(:initialize)
  end

  it "sets self into binary mode" do
    @ftp.binary.should be_nil
    @ftp.send(:initialize)
    @ftp.binary.should be_true
  end

  it "sets self into active mode" do
    @ftp.passive.should be_nil
    @ftp.send(:initialize)
    @ftp.passive.should be_false
  end

  it "sets self into non-debug mode" do
    @ftp.debug_mode.should be_nil
    @ftp.send(:initialize)
    @ftp.debug_mode.should be_false
  end

  it "sets self to not resume file uploads/downloads" do
    @ftp.resume.should be_nil
    @ftp.send(:initialize)
    @ftp.resume.should be_false
  end

  describe "when passed no arguments" do
    it "does not try to connect" do
      @ftp.should_not_receive(:connect)
      @ftp.send(:initialize)
    end
  end

  describe "when passed host" do
    it "tries to connect to the passed host" do
      @ftp.should_receive(:connect).with("localhost", *@port_args)
      @ftp.send(:initialize, "localhost")
    end
  end

  describe "when passed host, user" do
    it "tries to connect to the passed host" do
      @ftp.should_receive(:connect).with("localhost", *@port_args)
      @ftp.send(:initialize, "localhost")
    end

    it "tries to login with the passed username" do
      @ftp.should_receive(:login).with("rubyspec", nil, nil)
      @ftp.send(:initialize, "localhost", "rubyspec")
    end
  end

  describe "when passed host, user, password" do
    it "tries to connect to the passed host" do
      @ftp.should_receive(:connect).with("localhost", *@port_args)
      @ftp.send(:initialize, "localhost")
    end

    it "tries to login with the passed username and password" do
      @ftp.should_receive(:login).with("rubyspec", "rocks", nil)
      @ftp.send(:initialize, "localhost", "rubyspec", "rocks")
    end
  end

  describe "when passed host, user" do
    it "tries to connect to the passed host" do
      @ftp.should_receive(:connect).with("localhost", *@port_args)
      @ftp.send(:initialize, "localhost")
    end

    it "tries to login with the passed username, password and account" do
      @ftp.should_receive(:login).with("rubyspec", "rocks", "account")
      @ftp.send(:initialize, "localhost", "rubyspec", "rocks", "account")
    end
  end

  before :each do
    @ftp.stub!(:login)
  end

  describe 'when the host' do
    describe 'is set' do
      describe 'and port option' do
        describe 'is set' do
          it 'tries to connect to the host on the specified port' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({ port: 8080 })
            @ftp.should_receive(:connect).with('localhost', 8080)

            @ftp.send(:initialize, 'localhost', options)
          end
        end

        describe 'is not set' do
          it 'tries to connect to the host without a port' do
            @ftp.should_receive(:connect).with("localhost", *@port_args)

            @ftp.send(:initialize, 'localhost')
          end
        end
      end

      describe 'when the username option' do
        describe 'is set' do
          describe 'and the password option' do
            describe 'is set' do
              describe 'and the account option' do
                describe 'is set' do
                  it 'tries to log in with the supplied parameters' do
                    options = mock('ftp initialize options')
                    options.should_receive(:to_hash).and_return({ username: 'a', password: 'topsecret', account: 'b' })
                    @ftp.should_receive(:login).with('a', 'topsecret', 'b')

                    @ftp.send(:initialize, 'localhost', options)
                  end
                end

                describe 'is unset' do
                  it 'tries to log in with the supplied parameters' do
                    options = mock('ftp initialize options')
                    options.should_receive(:to_hash).and_return({ username: 'a', password: 'topsecret' })
                    @ftp.should_receive(:login).with('a', 'topsecret', nil)

                    @ftp.send(:initialize, 'localhost', options)
                  end
                end
              end
            end

            describe 'is unset' do
              describe 'and the account option' do
                describe 'is set' do
                  it 'tries to log in with the supplied parameters' do
                    options = mock('ftp initialize options')
                    options.should_receive(:to_hash).and_return({ username: 'a', account: 'b' })
                    @ftp.should_receive(:login).with('a', nil, 'b')

                    @ftp.send(:initialize, 'localhost', options)
                  end
                end

                describe 'is unset' do
                  it 'tries to log in with the supplied parameters' do
                    options = mock('ftp initialize options')
                    options.should_receive(:to_hash).and_return({ username: 'a'})
                    @ftp.should_receive(:login).with('a', nil, nil)

                    @ftp.send(:initialize, 'localhost', options)
                  end
                end
              end
            end
          end
        end

        describe 'is not set' do
          it 'does not try to log in' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({})
            @ftp.should_not_receive(:login)

            @ftp.send(:initialize, 'localhost', options)
          end
        end
      end
    end

    describe 'is unset' do
      it 'does not try to connect' do
        @ftp.should_not_receive(:connect)

        @ftp.send(:initialize)
      end

      it 'does not try to log in' do
        @ftp.should_not_receive(:login)

        @ftp.send(:initialize)
      end
    end
  end

  describe 'when the passive option' do
    describe 'is set' do
      describe 'to true' do
        it 'sets passive to true' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ passive: true })

          @ftp.send(:initialize, nil, options)
          @ftp.passive.should == true
        end
      end

      describe 'to false' do
        it 'sets passive to false' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ passive: false })

          @ftp.send(:initialize, nil, options)
          @ftp.passive.should == false
        end
      end
    end

    describe 'is unset' do
      it 'sets passive to false' do
        @ftp.send(:initialize)
        @ftp.passive.should == false
      end
    end
  end

  describe 'when the debug_mode option' do
    describe 'is set' do
      describe 'to true' do
        it 'sets debug_mode to true' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ debug_mode: true })

          @ftp.send(:initialize, nil, options)
          @ftp.debug_mode.should == true
        end
      end

      describe 'to false' do
        it 'sets debug_mode to false' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ debug_mode: false })

          @ftp.send(:initialize, nil, options)
          @ftp.debug_mode.should == false
        end
      end
    end

    describe 'is unset' do
      it 'sets debug_mode to false' do
        @ftp.send(:initialize)
        @ftp.debug_mode.should == false
      end
    end
  end

  describe 'when the open_timeout option' do
    describe 'is set' do
      it 'sets open_timeout to the specified value' do
        options = mock('ftp initialize options')
        options.should_receive(:to_hash).and_return({ open_timeout: 42 })

        @ftp.send(:initialize, nil, options)
        @ftp.open_timeout.should == 42
      end
    end

    describe 'is not set' do
      it 'sets open_timeout to nil' do
        @ftp.send(:initialize)
        @ftp.open_timeout.should == nil
      end
    end
  end

  describe 'when the read_timeout option' do
    describe 'is set' do
      it 'sets read_timeout to the specified value' do
        options = mock('ftp initialize options')
        options.should_receive(:to_hash).and_return({ read_timeout: 100 })

        @ftp.send(:initialize, nil, options)
        @ftp.read_timeout.should == 100
      end
    end

    describe 'is not set' do
      it 'sets read_timeout to the default value' do
        @ftp.send(:initialize)
        @ftp.read_timeout.should == 60
      end
    end
  end

  describe 'when the ssl_handshake_timeout option' do
    describe 'is set' do
      it 'sets ssl_handshake_timeout to the specified value' do
        options = mock('ftp initialize options')
        options.should_receive(:to_hash).and_return({ ssl_handshake_timeout: 23 })

        @ftp.send(:initialize, nil, options)
        @ftp.ssl_handshake_timeout.should == 23
      end
    end

    describe 'is not set' do
      it 'sets ssl_handshake_timeout to nil' do
        @ftp.send(:initialize)
        @ftp.ssl_handshake_timeout.should == nil
      end
    end
  end

  describe 'when the ssl option' do
    describe 'is set' do
      describe "and the ssl option's value is true" do
        it 'initializes ssl_context to a blank SSLContext object' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ ssl: true })

          ssl_context = OpenSSL::SSL::SSLContext.allocate
          ssl_context.stub!(:set_params)

          OpenSSL::SSL::SSLContext.should_receive(:new).and_return(ssl_context)
          ssl_context.should_receive(:set_params).with({})

          @ftp.send(:initialize, nil, options)
          @ftp.instance_variable_get(:@ssl_context).should == ssl_context
        end
      end

      describe "and the ssl option's value is a hash" do
        it 'initializes ssl_context to a configured SSLContext object' do
          options = mock('ftp initialize options')
          options.should_receive(:to_hash).and_return({ ssl: {key: 'value'} })

          ssl_context = OpenSSL::SSL::SSLContext.allocate
          ssl_context.stub!(:set_params)

          OpenSSL::SSL::SSLContext.should_receive(:new).and_return(ssl_context)
          ssl_context.should_receive(:set_params).with({key: 'value'})

          @ftp.send(:initialize, nil, options)
          @ftp.instance_variable_get(:@ssl_context).should == ssl_context
        end
      end

      describe 'and private_data_connection' do
        describe 'is set' do
          it 'sets private_data_connection to that value' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({ ssl: true, private_data_connection: 'true' })

            @ftp.send(:initialize, nil, options)
            @ftp.instance_variable_get(:@private_data_connection).should == 'true'
          end
        end

        describe 'is not set' do
          it 'sets private_data_connection to nil' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({ ssl: true })

            @ftp.send(:initialize, nil, options)
            @ftp.instance_variable_get(:@private_data_connection).should == true
          end
        end
      end
    end

    describe 'is not set' do
      it 'sets ssl_context to nil' do
        options = mock('ftp initialize options')
        options.should_receive(:to_hash).and_return({})

        @ftp.send(:initialize, nil, options)
        @ftp.instance_variable_get(:@ssl_context).should == nil
      end

      describe 'private_data_connection' do
        describe 'is set' do
          it 'raises an ArgumentError' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({ private_data_connection: true })

            -> {
              @ftp.send(:initialize, nil, options)
            }.should raise_error(ArgumentError, /private_data_connection can be set to true only when ssl is enabled/)
          end
        end

        describe 'is not set' do
          it 'sets private_data_connection to false' do
            options = mock('ftp initialize options')
            options.should_receive(:to_hash).and_return({})

            @ftp.send(:initialize, nil, options)
            @ftp.instance_variable_get(:@private_data_connection).should == false
          end
        end
      end
    end
  end
end
