require_relative '../config'

module Network
  def self.get(url, retries: CONFIG[:max_retries])
    attempts = 0
    begin
      attempts += 1
      response = HTTParty.get(url, timeout: 30)
      raise "HTTP #{response.code}" unless response.success?
      response.body
    rescue StandardError => e
      if attempts < retries
        LOGGER.warn("Tentativa #{attempts}/#{retries} falhou para #{url}: #{e.message}. Retrying...")
        sleep CONFIG[:retry_delay]
        retry
      end
      raise
    end
  end
end
