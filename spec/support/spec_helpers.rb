module SpecHelpers
  def strip_eom_block(block)
    if block =~ /^(\s+)/m
      block.gsub!(/^#{$1}/, "")
    else
      block
    end
  end
end
