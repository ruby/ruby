require_relative '../did_you_mean'
require_relative 'formatters/verbose_formatter'

DidYouMean.formatter = DidYouMean::VerboseFormatter.new
