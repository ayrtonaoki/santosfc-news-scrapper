require 'net/http'
require 'json'
require_relative '../config'

class Summarizer
  def initialize
    @uri     = URI("http://#{CONFIG[:ai_host]}:#{CONFIG[:ai_port]}/api/chat")
    @model   = CONFIG[:ai_model]
    @timeout = CONFIG[:ai_timeout]
    @prompt  = CONFIG[:summary_prompt]
  end

  def call(text, retries: CONFIG[:max_retries])
    attempts = 0

    begin
      attempts += 1
      body     = build_request_body(text)
      response = post(body)
      parse_response(response)

    rescue StandardError => e
      if attempts < retries
        LOGGER.warn("Tentativa #{attempts}/#{retries} no summarizer falhou: #{e.message}. Retrying...")
        sleep CONFIG[:retry_delay]
        retry
      end
      raise
    end
  end

  private

  def build_request_body(text)
    {
      model:    @model,
      messages: [{ role: "user", content: @prompt % text }],
      stream:   false
    }.to_json
  end

  def post(body)
    req      = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
    req.body = body

    Net::HTTP.start(@uri.hostname, @uri.port, read_timeout: @timeout) do |http|
      http.request(req)
    end
  end

  def parse_response(response)
    JSON.parse(response.body).dig("message", "content") ||
      raise("Resposta inesperada da IA: #{response.body[0..200]}")
  end
end
