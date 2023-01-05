require 'optparse'
parser = OptionParser.new(
  'ruby help_format.rb [options]', # Banner
  20,                               # Width of options field
  ' ' * 2                               # Indentation
)
parser.on(
  '-x', '--xxx',
  'Adipiscing elit. Aenean commodo ligula eget.',
  'Aenean massa. Cum sociis natoque penatibus',
  )
parser.on(
  '-y', '--yyy YYY',
  'Lorem ipsum dolor sit amet, consectetuer.'
)
parser.on(
  '-z', '--zzz [ZZZ]',
  'Et magnis dis parturient montes, nascetur',
  'ridiculus mus. Donec quam felis, ultricies',
  'nec, pellentesque eu, pretium quis, sem.',
  )
parser.parse!
