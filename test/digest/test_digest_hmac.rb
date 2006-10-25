require 'pathname'
require Pathname.new(__FILE__).dirname.join('../inlinetest.rb')
InlineTest.loadtest__END__part('digest/hmac.rb')
