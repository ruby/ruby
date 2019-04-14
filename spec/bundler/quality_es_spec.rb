# frozen_string_literal: true

if defined?(Encoding) && Encoding.default_external.name != "UTF-8"
  # An approximation of ruby -E UTF-8, since it works on 1.8.7
  Encoding.default_external = Encoding.find("UTF-8")
end

RSpec.describe "La biblioteca si misma" do
  def check_for_expendable_words(filename)
    failing_line_message = []
    useless_words = %w[
      básicamente
      claramente
      sólo
      solamente
      obvio
      obviamente
      fácil
      fácilmente
      sencillamente
      simplemente
    ]
    pattern = /\b#{Regexp.union(useless_words)}\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = pattern.match(line)
      failing_line_message << "#{filename}:#{number.succ} contiene '#{word_found}'. Esta palabra tiene un significado subjetivo y es mejor obviarla en textos técnicos."
    end

    failing_line_message unless failing_line_message.empty?
  end

  def check_for_specific_pronouns(filename)
    failing_line_message = []
    specific_pronouns = /\b(él|ella|ellos|ellas)\b/i

    File.readlines(filename).each_with_index do |line, number|
      next unless word_found = specific_pronouns.match(line)
      failing_line_message << "#{filename}:#{number.succ} contiene '#{word_found}'. Use pronombres más genéricos en la documentación."
    end

    failing_line_message unless failing_line_message.empty?
  end

  it "mantiene la calidad de lenguaje de la documentación" do
    included = /ronn/
    error_messages = []
    Dir.chdir(root) do
      `git ls-files -z -- man`.split("\x0").each do |filename|
        next unless filename =~ included
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end

  it "mantiene la calidad de lenguaje de oraciones usadas en el código fuente", :ruby_repo do
    error_messages = []
    exempt = /vendor/
    Dir.chdir(root) do
      `git ls-files -z -- lib`.split("\x0").each do |filename|
        next if filename =~ exempt
        error_messages << check_for_expendable_words(filename)
        error_messages << check_for_specific_pronouns(filename)
      end
    end
    expect(error_messages.compact).to be_well_formed
  end
end
