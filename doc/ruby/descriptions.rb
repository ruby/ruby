require 'optparse'
parser = OptionParser.new
description = <<-EOT
Lorem ipsum dolor sit amet, consectetuer
adipiscing elit. Aenean commodo ligula eget.
Aenean massa. Cum sociis natoque penatibus
et magnis dis parturient montes, nascetur
ridiculus mus. Donec quam felis, ultricies
nec, pellentesque eu, pretium quis, sem.
EOT
descriptions = description.split($/)
parser.on('--xxx', *descriptions) do |value|
  p ['--xxx', value]
end
parser.parse!
