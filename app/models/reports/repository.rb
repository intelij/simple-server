module Reports
  class Repository
    def initialize(regions, periods:, with_exclusions: false)
      @regions = Array(regions)
      @regions_by_id = @regions.group_by { |r| r.id }
      @with_exclusions = with_exclusions

      @periods = if periods.is_a?(Period)
        Range.new(periods, periods).to_a
      else
        periods.to_a
      end
    end

    attr_reader :regions, :periods
    attr_reader :regions_by_id
    attr_reader :with_exclusions

    delegate :cache, :logger, to: Rails
    def for_region_and_period(region, period)
      raise ArgumentError, "Repository does not include region #{region.slug}" unless regions.include?(region)
      raise ArgumentError, "Repository does not include period #{period}" unless periods.include?(period)
      RegionAndPeriodFetcher.new(self, region, period)
    end

    # Returns assigned_patient counts in the shape of
    # {
    #    region_slug: { period: value },
    #    region_slug: { period: value }
    # }
    def assigned_patients_count
      items = regions.map { |region| RegionItem.new(region, :assigned_patients_count, with_exclusions: with_exclusions) }

      cached_results = cache.fetch_multi(*items, force: force_cache?) { |item|
        AssignedPatientsQuery.new.count(item.region, :month, with_exclusions: with_exclusions)
      }
      cached_results.each_with_object({}) do |(item, result), results|
        results[item.region.slug] = result
      end
    end

    def controlled_patients_count
      cached_query(:controlled_patients_count) do |item|
        control_rate_query.controlled(item.region, item.period, with_exclusions: with_exclusions).count
      end
    end

    def uncontrolled_patients_count
      cached_query(:uncontrolled_patients_count) do |item|
        control_rate_query.uncontrolled(item.region, item.period, with_exclusions: with_exclusions).count
      end
    end

    def no_bp_measure_count
      cached_query(:no_bp_measure_count) do |item|
        no_bp_measure_query.call(item.region, item.period, with_exclusions: with_exclusions)
      end
    end

    private

    # Generate all necessary cache keys for a calculation, then yield to the block with every Item.
    # Once all results are returned via fetch_multi, return the data in a standard format of:
    #   {
    #     region_1_slug: { period_1: value, period_2: value }
    #     region_2_slug: { period_1: value, period_2: value }
    #   }
    #
    def cached_query(calculation, &block)
      items = cache_keys(calculation)
      cached_results = cache.fetch_multi(*items, force: force_cache?) { |item|
        block.call(item)
      }
      cached_results.each_with_object({}) do |(item, count), results|
        results[item.region.slug] ||= Hash.new(0)
        results[item.region.slug][item.period] = count
      end
    end

    def cache_keys(calculation)
      combinations = regions.to_a.product(periods)
      combinations.map { |region, period| Reports::Item.new(region, period, calculation, with_exclusions: with_exclusions) }
    end

    def no_bp_measure_query
      @query ||= NoBPMeasureQuery.new
    end

    def control_rate_query
      @control_rate_query ||= ControlRateQuery.new
    end

    def force_cache?
      RequestStore.store[:force_cache]
    end
  end
end
