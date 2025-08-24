class AlertRulesController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_alert_rule, only: [:show, :edit, :update, :destroy, :toggle]

  def index
    @alert_rules = @project.alert_rules.order(:name)
    @alert_notifications = @project.alert_notifications.recent.limit(20)
  end

  def show
    @recent_notifications = @alert_rule.alert_notifications.recent.limit(10)
  end

  def new
    @alert_rule = @project.alert_rules.build
  end

  def create
    @alert_rule = @project.alert_rules.build(alert_rule_params)

    if @alert_rule.save
      redirect_to project_alert_rules_path(@project),
                  notice: 'Alert rule created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @alert_rule.update(alert_rule_params)
      redirect_to project_alert_rules_path(@project),
                  notice: 'Alert rule updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @alert_rule.destroy
    redirect_to project_alert_rules_path(@project),
                notice: 'Alert rule deleted successfully.'
  end

  def toggle
    @alert_rule.update!(enabled: !@alert_rule.enabled)
    status = @alert_rule.enabled? ? 'enabled' : 'disabled'
    redirect_to project_alert_rules_path(@project),
                notice: "Alert rule #{status}."
  end

  def test_alert
    @alert_rule = @project.alert_rules.find(params[:id])

    # Send a test alert
    test_payload = generate_test_payload(@alert_rule)
    AlertJob.perform_async(@alert_rule.id, @alert_rule.rule_type, test_payload)

    redirect_to project_alert_rule_path(@project, @alert_rule),
                notice: 'Test alert queued. Check your notifications.'
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end

  def set_alert_rule
    @alert_rule = @project.alert_rules.find(params[:id])
  end

  def alert_rule_params
    params.require(:alert_rule).permit(
      :name, :rule_type, :threshold_value, :time_window_minutes,
      :cooldown_minutes, :enabled, conditions: {}
    )
  end

  def generate_test_payload(alert_rule)
    case alert_rule.rule_type
    when 'error_frequency'
      {
        issue_id: @project.issues.first&.id || 1,
        count: alert_rule.threshold_value + 1,
        time_window: alert_rule.time_window_minutes,
        test: true
      }
    when 'performance_regression'
      {
        event_id: @project.events.performance.first&.id || 1,
        duration_ms: alert_rule.threshold_value + 100,
        controller_action: 'TestController#test_action',
        test: true
      }
    when 'n_plus_one'
      {
        incidents: [
          {
            sql_fingerprint: { query_type: 'SELECT', normalized_query: 'SELECT * FROM users WHERE id = ?' },
            count_in_request: 10,
            severity: 'high'
          }
        ],
        controller_action: 'TestController#test_action',
        test: true
      }
    when 'new_issue'
      {
        issue_id: @project.issues.first&.id || 1,
        test: true
      }
    else
      { test: true }
    end
  end
end
