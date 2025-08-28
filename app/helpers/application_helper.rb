module ApplicationHelper
  # Toggle this logic to decide when to show the sidebar
  def show_sidebar?
    # Show sidebar on admin/dashboard pages
    controller_path.start_with?("admin") ||
    request.path.start_with?("/dashboard") ||
    %w[dashboard errors performance security logs settings deploys projects].include?(controller_name) ||
    controller_path.include?("project_settings") ||
    controller_path.include?("account_settings")
  end
end
