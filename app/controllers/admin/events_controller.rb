class Admin::EventsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_event, only: [:show, :destroy]

  def index
    @events = @project.events.includes(:issue, :release)

    # Filtering
    @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
    @events = @events.where(environment: params[:environment]) if params[:environment].present?
    @events = @events.where('controller_action ILIKE ?', "%#{params[:controller_action]}%") if params[:controller_action].present?
    @events = @events.joins(:issue).where(issues: { id: params[:issue_id] }) if params[:issue_id].present?

    # Date filtering
    if params[:date_from].present?
      @events = @events.where('occurred_at >= ?', Date.parse(params[:date_from]))
    end
    if params[:date_to].present?
      @events = @events.where('occurred_at <= ?', Date.parse(params[:date_to]).end_of_day)
    end

    @events = @events.order(occurred_at: :desc).page(params[:page]).per(50)

    # Stats
    @stats = {
      total_today: @project.events.where('occurred_at > ?', 24.hours.ago).count,
      errors_today: @project.events.errors.where('occurred_at > ?', 24.hours.ago).count,
      performance_today: @project.events.performance.where('occurred_at > ?', 24.hours.ago).count,
      avg_response_time: @project.events.performance
                                .where('occurred_at > ? AND duration_ms IS NOT NULL', 24.hours.ago)
                                .average(:duration_ms)&.round(2)
    }

    # Environment breakdown
    @environments = @project.events.group(:environment).count
  end

  def show
    @formatted_payload = JSON.pretty_generate(@event.payload)
  end

  def destroy
    @event.destroy
    redirect_to admin_project_events_path(@project), notice: 'Event deleted successfully.'
  end

  def bulk_delete
    event_ids = params[:event_ids] || []

    if event_ids.empty?
      redirect_to admin_project_events_path(@project), alert: 'No events selected.'
      return
    end

    count = @project.events.where(id: event_ids).count
    @project.events.where(id: event_ids).destroy_all

    redirect_to admin_project_events_path(@project), notice: "#{count} events deleted."
  end

  def cleanup_old
    # Delete events older than specified days
    days = params[:days]&.to_i || 90

    if days < 7
      redirect_to admin_project_events_path(@project), alert: 'Minimum retention period is 7 days.'
      return
    end

    count = @project.events.where('created_at < ?', days.days.ago).count
    @project.events.where('created_at < ?', days.days.ago).destroy_all

    redirect_to admin_project_events_path(@project), notice: "#{count} old events deleted (older than #{days} days)."
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end

  def set_event
    @event = @project.events.find(params[:id])
  end
end
