module ApplicationHelper
  # Include Pagy frontend for pagination
  include Pagy::Frontend

  # Toggle this logic to decide when to show the sidebar
  def show_sidebar?
    # Show sidebar on admin/dashboard pages
    controller_path.start_with?("admin") ||
    request.path.start_with?("/dashboard") ||
    %w[dashboard errors performance security logs settings deploys projects].include?(controller_name) ||
    controller_path.include?("project_settings") ||
    controller_path.include?("account_settings")
  end

  # Unified helper for errors index path that respects project scoping (global, project_id, or slug)
  def errors_index_path(options = {})
    if defined?(@current_project) && @current_project
      project_slug_errors_path(@current_project.slug, options)
    elsif defined?(@project) && @project
      project_errors_path(@project, options)
    else
      errors_path(options)
    end
  end
end
