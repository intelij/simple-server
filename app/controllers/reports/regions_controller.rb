class Reports::RegionsController < AdminController
  layout "application"
  skip_after_action :verify_policy_scoped
  before_action :set_force_cache
  before_action :set_selected_date, except: :index
  before_action :find_region, except: :index
  around_action :set_time_zone

  def index
    authorize(:dashboard, :show?)

    @organizations = policy_scope([:cohort_report, Organization]).order(:name)
  end

  def show
    authorize(:dashboard, :show?)

    @data = RegionReportService.new(region: @region,
                                    selected_date: @selected_date,
                                    period: @period,
                                    current_user: current_admin).call
    @controlled_patients = @data[:controlled_patients]
    @registrations = @data[:registrations]
    @quarterly_registrations = @data[:quarterly_registrations]
    @top_region_benchmarks = @data[:top_region_benchmarks]
    @last_registration_value = @data[:registrations].values&.last || 0
  end

  def details
    authorize(:dashboard, :show?)

    @data = RegionReportService.new(region: @region,
                                    selected_date: @selected_date,
                                    current_user: current_admin).call
    @controlled_patients = @data[:controlled_patients]
    @registrations = @data[:registrations]
    @quarterly_registrations = @data[:quarterly_registrations]
    @top_region_benchmarks = @data[:top_region_benchmarks]
    @last_registration_value = @data[:registrations].values&.last || 0
  end

  def cohort
    authorize(:dashboard, :show?)

    @data = RegionReportService.new(region: @region,
                                    selected_date: @selected_date,
                                    current_user: current_admin).call
    @controlled_patients = @data[:controlled_patients]
    @registrations = @data[:registrations]
    @quarterly_registrations = @data[:quarterly_registrations]
    @top_region_benchmarks = @data[:top_region_benchmarks]
    @last_registration_value = @data[:registrations].values&.last || 0
  end

  private

  def set_selected_date
    @period = facility_params[:period] || "month"
    @selected_date = if facility_params[:selected_date]
      Time.parse(facility_params[:selected_date])
    else
      Date.current.advance(months: -1)
    end
  end

  def set_force_cache
    RequestStore.store[:force_cache] = true if force_cache?
  end

  def find_region
    region_class, slug = facility_params[:id].split("-")
    unless region_class.in?(["facility_group", "facility"])
      raise ActiveRecord::RecordNotFound
    end
    klass = region_class.classify.constantize
    @region = klass.find_by!(slug: slug)
  end

  def facility_params
    params.permit(:selected_date, :id, :force_cache, :period, :report_scope)
  end

  def force_cache?
    facility_params[:force_cache].present?
  end

  def set_time_zone
    time_zone = Rails.application.config.country[:time_zone] || DEFAULT_ANALYTICS_TIME_ZONE

    Groupdate.time_zone = time_zone

    Time.use_zone(time_zone) { yield }
    Groupdate.time_zone = "UTC"
  end
end