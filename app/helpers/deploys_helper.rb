module DeploysHelper
  def live_for_human(deploy)
    seconds = deploy.live_for_seconds.to_i
    return "just now" if seconds < 60

    minutes = seconds / 60
    return "#{minutes}m" if minutes < 60

    hours = minutes / 60
    return "#{hours}h" if hours < 24

    days = hours / 24
    return "#{days}d" if days < 7

    weeks = days / 7
    remaining_days = days % 7

    remaining_days.zero? ? "#{weeks}w" : "#{weeks}w #{remaining_days}d"
  end
end
