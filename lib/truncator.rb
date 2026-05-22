require_relative '../config'

module Truncator
  def self.call(paragraphs, max_chars: CONFIG[:max_chars])
    result = []
    total  = 0

    paragraphs.each do |p|
      break if total + p.length > max_chars
      result << p
      total += p.length
    end

    result.join("\n")
  end
end
