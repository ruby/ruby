require 'pathname'
require Pathname.new(__FILE__).parent.join('inlinetest.rb')
target = __FILE__.scan(/test_(.*\.rb)$/)[0][0]
InlineTest.loadtest__END__part(target)
