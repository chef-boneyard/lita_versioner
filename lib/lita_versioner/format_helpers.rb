module LitaVersioner
  module FormatHelpers
    def how_long_ago(start_time)
      days, hours = duration.divmod(24)
      hours, minutes = hours.divmod(60)
      minutes, seconds = minutes.divmod(60)
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
      hours, minutes = duration.divmod(60)
      minutes, seconds = minutes.divmod(60)
      "#{"%.2d" % hours}:#{"%.2d" % minutes}:#{"%.2d" % seconds}"
    end
  end
end
