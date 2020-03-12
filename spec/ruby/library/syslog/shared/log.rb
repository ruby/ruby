describe :syslog_log, shared: true do
  platform_is_not :windows, :darwin, :solaris, :aix do
    before :each do
      Syslog.opened?.should be_false
    end

    after :each do
      Syslog.opened?.should be_false
    end

    it "logs a message" do
      -> {
        Syslog.open("rubyspec", Syslog::LOG_PERROR) do
          Syslog.send(@method, "Hello")
        end
      }.should output_to_fd(/\Arubyspec(?::| \d+ - -) Hello\n\z/, $stderr)
    end

    it "accepts sprintf arguments" do
      -> {
        Syslog.open("rubyspec", Syslog::LOG_PERROR) do
          Syslog.send(@method, "Hello %s", "world")
          Syslog.send(@method, "%d dogs", 2)
        end
      }.should output_to_fd(/\Arubyspec(?::| \d+ - -) Hello world\nrubyspec(?::| \d+ - -) 2 dogs\n\z/, $stderr)
    end

    it "works as an alias for Syslog.log" do
      level = Syslog.const_get "LOG_#{@method.to_s.upcase}"
      -> {
        Syslog.open("rubyspec", Syslog::LOG_PERROR) do
          Syslog.send(@method, "Hello")
          Syslog.log(level, "Hello")
        end
        # make sure the same thing is written to $stderr.
      }.should output_to_fd(/\A(?:rubyspec(?::| \d+ - -) Hello\n){2}\z/, $stderr)
    end
  end
end
