require_relative 'other-lang/ack'

def the_answer_to_life_the_universe_and_everything
  (ack(3,7).to_s.split(//).inject(0){|s,x| s+x.to_i}.to_s + "2" ).to_i
end

answer = the_answer_to_life_the_universe_and_everything