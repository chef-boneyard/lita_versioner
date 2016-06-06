module LitaVersioner
  module FormatHelpers
    def how_long_ago(start_time)
      duration = Time.now.utc - start_time
      minutes, seconds = duration.divmod(60)
      hours, minutes = minutes.divmod(60)
      days, hours = hours.divmod(24)
      parts = []
      parts << "#{days} day#{days > 1 ? "s" : ""}" if days > 0
      parts << "#{hours} hour#{hours > 1 ? "s" : ""}" if hours > 0
      parts << "#{minutes} minute#{minutes > 1 ? "s" : ""}" if minutes > 0
      parts << "#{seconds} second#{seconds > 1 ? "s" : ""}" if days > 0
      case parts.size
      when 0
        "just now"
      when 1
        "#{parts[0]} ago"
      else
        "#{parts[0..-2].join(", ")} and #{parts[-1]} ago"
      end
    end

    def format_duration(duration)
      minutes, seconds = duration.divmod(60)
      hours, minutes = minutes.divmod(60)
      "#{"%.2d" % hours}:#{"%.2d" % minutes}:#{"%.2d" % seconds}"
    end
  end
end
