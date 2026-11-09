module ClinicManagement
  # Strategic read-only insights over existing clinic visits and prescriptions.
  # ESSENTIAL: All data follows the current service-location context, as services#index does.
  class AnalyticsController < ApplicationController
    before_action :require_analytics_access!

    def index
      set_analytics_filters
      @regions = Region.active.order(:name).pluck(:name, :id)
      @referrals = Referral.order(:name).pluck(:name, :id)
      @referral_ranking = Analytics::ReferralRanking.new(
        start_date: @start_date, end_date: @end_date,
        service_location_id: current_service_location_id, region_id: @region_id
      ).call(referrals: @referrals)
      @analytics = analytics_for(@start_date, @end_date, include_shift_financials: request.format.csv?)
      if @compare_previous
        period_days = (@end_date - @start_date).to_i + 1
        @previous_end_date = @start_date - 1.day
        @previous_start_date = @previous_end_date - (period_days - 1).days
        @previous_analytics = analytics_for(@previous_start_date, @previous_end_date)
      end

      if request.format.html? && params[:detail].present?
        @detail = Analytics::Drilldown.new(
          start_date: @start_date, end_date: @end_date,
          service_location_id: current_service_location_id,
          region_id: @region_id, referral_id: @referral_id,
          include_sales: helpers.services_sales_metrics_available?
        ).call(dimension: params[:detail], value: params[:value], page: params[:detail_page])
      end

      respond_to do |format|
        format.html
        format.csv do
          filters = {
            "Unidade" => current_service_location_id.presence || "Interna",
            "Região" => @regions.find { |_, id| id == @region_id }&.first || "Todas",
            "Origem / captador" => @referrals.find { |_, id| id == @referral_id }&.first || "Todas"
          }
          send_data Analytics::CsvExport.new(@analytics, start_date: @start_date, end_date: @end_date, filters: filters).call,
                    filename: "inteligencia-atendimentos-#{@start_date}-#{@end_date}.csv",
                    type: "text/csv; charset=utf-8", disposition: "attachment"
        end
      end
    end

    # Requested only by the explicit button in the report. Turbo replaces just
    # this frame, without reloading the rest of the analytics dashboard.
    def shift_financials
      return head :forbidden unless helpers.services_sales_metrics_available?

      set_analytics_filters
      @service_statistics_backfill_enqueued = ServiceStatistics::Bootstrap.enqueue_once! if @region_id.nil? && @referral_id.nil?
      @analytics = analytics_for(@start_date, @end_date, include_shift_financials: true)
      render :shift_financials, layout: false
    end

    private

    # Resolve all comparisons through the same filters, including service location.
    def analytics_for(start_date, end_date, include_shift_financials: false)
      Analytics::Overview.new(
        start_date: start_date,
        end_date: end_date,
        service_location_id: current_service_location_id,
        region_id: @region_id,
        referral_id: @referral_id,
        include_sales: helpers.services_sales_metrics_available?,
        include_shift_financials: include_shift_financials
      ).call
    end

    def set_analytics_filters
      @end_date = parse_date(params[:end_date], Date.current)
      @start_date = parse_date(params[:start_date], @end_date - 89.days)
      @start_date, @end_date = @end_date, @start_date if @start_date > @end_date
      @start_date = [@start_date, @end_date - 365.days].max
      @region_id = positive_id(params[:region_id])
      @referral_id = positive_id(params[:referral_id])
      @compare_previous = params[:compare] == "previous"
      @ranking_metric = %w[exams average_sales_amount average_receipts_amount].include?(params[:ranking_metric]) ? params[:ranking_metric] : "exams"
      @region_view = %w[invitation customer compare].include?(params[:region_view]) ? params[:region_view] : "invitation"
      @filter_params = {
        start_date: @start_date.iso8601, end_date: @end_date.iso8601,
        region_id: @region_id, referral_id: @referral_id,
        compare: (@compare_previous ? "previous" : nil),
        ranking_metric: (@ranking_metric == "exams" ? nil : @ranking_metric),
        region_view: (@region_view == "invitation" ? nil : @region_view)
      }.compact
    end

    def positive_id(value)
      id = Integer(value, exception: false)
      id if id&.positive?
    end

    # Keep dates bounded to avoid unintentional full-history requests.
    def parse_date(value, fallback)
      Date.iso8601(value.to_s)
    rescue Date::Error
      fallback
    end

    # ESSENTIAL: Metrics are managerial, even when retail sales are disabled.
    def require_analytics_access!
      return if analytics_access_allowed?

      redirect_to services_path, alert: "Você não tem permissão para acessar estes indicadores."
    end
  end
end
