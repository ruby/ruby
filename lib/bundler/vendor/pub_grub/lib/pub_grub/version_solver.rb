require_relative 'partial_solution'
require_relative 'term'
require_relative 'incompatibility'
require_relative 'solve_failure'
require_relative 'strategy'

module Bundler::PubGrub
  class VersionSolver
    attr_reader :logger
    attr_reader :source
    attr_reader :solution
    attr_reader :strategy

    def initialize(source:, root: Package.root, strategy: Strategy.new(source), logger: Bundler::PubGrub.logger)
      @logger = logger

      @source = source
      @strategy = strategy

      # { package => [incompatibility, ...]}
      @incompatibilities = Hash.new do |h, k|
        h[k] = []
      end

      @seen_incompatibilities = {}

      @solution = PartialSolution.new

      add_incompatibility Incompatibility.new([
        Term.new(VersionConstraint.any(root), false)
      ], cause: :root)

      propagate(root)
    end

    def solved?
      solution.unsatisfied.empty?
    end

    # Returns true if there is more work to be done, false otherwise
    def work
      unsatisfied_terms = solution.unsatisfied
      if unsatisfied_terms.empty?
        logger.info { "Solution found after #{solution.attempted_solutions} attempts:" }
        solution.decisions.each do |package, version|
          next if Package.root?(package)
          logger.info { "* #{package} #{version}" }
        end

        return false
      end

      next_package = choose_package_version_from(unsatisfied_terms)
      propagate(next_package)

      true
    end

    def solve
      while work; end

      solution.decisions
    end

    alias_method :result, :solve

    private

    def propagate(initial_package)
      changed = [initial_package]
      while package = changed.shift
        @incompatibilities[package].reverse_each do |incompatibility|
          result = propagate_incompatibility(incompatibility)
          if result == :conflict
            root_cause = resolve_conflict(incompatibility)
            changed.clear
            changed << propagate_incompatibility(root_cause)
          elsif result # should be a Package
            changed << result
          end
        end
        changed.uniq!
      end
    end

    def propagate_incompatibility(incompatibility)
      unsatisfied = nil
      incompatibility.terms.each do |term|
        relation = solution.relation(term)
        if relation == :disjoint
          return nil
        elsif relation == :overlap
          # If more than one term is inconclusive, we can't deduce anything
          return nil if unsatisfied
          unsatisfied = term
        end
      end

      if !unsatisfied
        return :conflict
      end

      logger.debug { "derived: #{unsatisfied.invert}" }

      solution.derive(unsatisfied.invert, incompatibility)

      unsatisfied.package
    end

    def choose_package_version_from(unsatisfied_terms)
      remaining = unsatisfied_terms.map { |t| [t.package, t.constraint.range] }.to_h

      package, version = strategy.next_package_and_version(remaining)

      logger.debug { "attempting #{package} #{version}" }

      if version.nil?
        unsatisfied_term = unsatisfied_terms.find { |t| t.package == package }
        add_incompatibility source.no_versions_incompatibility_for(package, unsatisfied_term)
        return package
      end

      conflict = false

      source.incompatibilities_for(package, version).each do |incompatibility|
        if @seen_incompatibilities.include?(incompatibility)
          logger.debug { "knew: #{incompatibility}" }
          next
        end
        @seen_incompatibilities[incompatibility] = true

        add_incompatibility incompatibility

        conflict ||= incompatibility.terms.all? do |term|
          term.package == package || solution.satisfies?(term)
        end
      end

      unless conflict
        logger.info { "selected #{package} #{version}" }

        solution.decide(package, version)
      else
        logger.info { "conflict: #{conflict.inspect}" }
      end

      package
    end

    def resolve_conflict(incompatibility)
      logger.info { "conflict: #{incompatibility}" }

      new_incompatibility = nil

      while !incompatibility.failure?
        most_recent_term = nil
        most_recent_satisfier = nil
        difference = nil

        previous_level = 1

        incompatibility.terms.each do |term|
          satisfier = solution.satisfier(term)

          if most_recent_satisfier.nil?
            most_recent_term = term
            most_recent_satisfier = satisfier
          elsif most_recent_satisfier.index < satisfier.index
            previous_level = [previous_level, most_recent_satisfier.decision_level].max
            most_recent_term = term
            most_recent_satisfier = satisfier
            difference = nil
          else
            previous_level = [previous_level, satisfier.decision_level].max
          end

          if most_recent_term == term
            difference = most_recent_satisfier.term.difference(most_recent_term)
            if difference.empty?
              difference = nil
            else
              difference_satisfier = solution.satisfier(difference.inverse)
              previous_level = [previous_level, difference_satisfier.decision_level].max
            end
          end
        end

        if previous_level < most_recent_satisfier.decision_level ||
            most_recent_satisfier.decision?

          logger.info { "backtracking to #{previous_level}" }
          solution.backtrack(previous_level)

          if new_incompatibility
            add_incompatibility(new_incompatibility)
          end

          return incompatibility
        end

        new_terms = []
        new_terms += incompatibility.terms - [most_recent_term]
        new_terms += most_recent_satisfier.cause.terms.reject { |term|
          term.package == most_recent_satisfier.term.package
        }
        if difference
          new_terms << difference.invert
        end

        new_incompatibility = Incompatibility.new(new_terms, cause: Incompatibility::ConflictCause.new(incompatibility, most_recent_satisfier.cause))

        if incompatibility.to_s == new_incompatibility.to_s
          logger.info { "!! failed to resolve conflicts, this shouldn't have happened" }
          break
        end

        incompatibility = new_incompatibility

        partially = difference ? " partially" : ""
        logger.info { "! #{most_recent_term} is#{partially} satisfied by #{most_recent_satisfier.term}" }
        logger.info { "! which is caused by #{most_recent_satisfier.cause}" }
        logger.info { "! thus #{incompatibility}" }
      end

      raise SolveFailure.new(incompatibility)
    end

    def add_incompatibility(incompatibility)
      logger.debug { "fact: #{incompatibility}" }
      incompatibility.terms.each do |term|
        package = term.package
        @incompatibilities[package] << incompatibility
      end
    end
  end
end
