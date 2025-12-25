module DeploysHelper
  def live_for_human(deploy, next_deploy)
    seconds = deploy.live_for_seconds(next_deploy)

    minutes = seconds / 60
    return "#{minutes}m" if minutes < 60

    hours = minutes / 60
    return "#{hours}h" if hours < 24

    days = hours / 24
    "#{days}d"
  end

  def progress_percent(value, max)
    return 0 if max.zero?
    ((value.to_f / max) * 100).round
  end
end
