module SpecHelpers
  def strip_eom_block(block)
    if block =~ /^(\s+)/m
      block.gsub!(/^#{$1}/, "")
    else
      block
    end
  end

  TIMESTAMP_SIZE = "2016-06-07 02:45:52 UTC ".size
  def strip_log_data(log)
    log = log.gsub(/^\[.{#{TIMESTAMP_SIZE}}/, "[")
    log.gsub(tmpdir, "/TMPDIR")
  end

  # Allow things to take 1 second extra and still match
  def one_second_slop(log)
    log.gsub("after 1 second", "after 0 seconds")
  end
end
