require 'httparty'
require 'nokogiri'
require 'net/http'
require 'json'
require 'logger'

CONFIG = {
  base_url:     "https://ge.globo.com/sp/santos-e-regiao/futebol/times/santos/",
  ai_model:     "llama3",
  ai_host:      "localhost",
  ai_port:      11_434,
  ai_timeout:   300,
  max_chars:    6_000,
  max_retries:  3,
  retry_delay:  2
}.freeze

SEPARATOR = "=" * 90

LOGGER = Logger.new($stdout).tap do |l|
  l.formatter = proc { |severity, _datetime, _progname, msg|
    "[#{Time.now.strftime('%H:%M:%S')}] #{msg}\n"
  }
  l.level = Logger::INFO
end

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

module Reporter
  def self.print_article(data)
    puts "\n#{SEPARATOR}"
    puts "\n#{data[:title].upcase}"
    puts data[:subtitle]
    puts data[:summary]
  end
end

class Pipeline
  def initialize
    @scraper    = Scraper.new(CONFIG[:base_url])
    @summarizer = Summarizer.new
    @results    = []
  end

  def run
    LOGGER.info("Iniciando...")

    links = @scraper.article_links

    links.each do |link|
      result = process_article(link)
      next unless result

      @results << result
      Reporter.print_article(result)
    end

    puts "\n#{SEPARATOR}\n\n"
    LOGGER.info("Script finalizado! #{@results.size}/#{links.size} matérias processadas.")
  end

  private

  def process_article(link)
    article = scrape_safely(link)
    return unless article

    summary = summarize_safely(article)
    return unless summary

    article.merge(summary:)
  rescue StandardError => e
    LOGGER.error("Erro inesperado em #{link}: #{e.message}")
    nil
  end

  def scrape_safely(link)
    @scraper.scrape_article(link)
  rescue StandardError => e
    LOGGER.error("Falha ao baixar matéria: #{e.message} | #{link}")
    nil
  end

  def summarize_safely(article)
    text = Truncator.call(article[:paragraphs])
    return nil if text.empty?

    @summarizer.call(text)
  rescue StandardError => e
    LOGGER.warn("Falha no resumo: #{e.message}")
    nil
  end
end

class Scraper
  def initialize(base_url)
    @base_url = base_url
  end

  def article_links
    LOGGER.info("Baixando página principal...")
    html  = Network.get(@base_url)
    doc   = Nokogiri::HTML(html)

    links = doc.css("a[href]")
               .map { |a| a["href"] }
               .select { |href| href.to_s.match?(%r{/sp/santos-e-regiao/futebol/times/santos/noticia/}) }
               .select { |href| href.end_with?(".ghtml") }
               .map { |href| href.start_with?("http") ? href : "https://ge.globo.com#{href}" }
               .uniq

    LOGGER.info("Total de matérias encontradas: #{links.size}")
    links
  end

  def scrape_article(url)
    html = Network.get(url)
    doc  = Nokogiri::HTML(html)

    title = doc.at_css("h1")&.text&.strip || "(sem título)"
    subtitle = doc.at_css(".content-head__subtitle")&.text&.strip

    paragraphs = doc.css(".mc-article-body p")
                    .map { |p| p.text.strip }
                    .reject(&:empty?)

    { url:, title:, subtitle:, paragraphs: }
  end
end

class Summarizer
  def initialize
    @uri     = URI("http://#{CONFIG[:ai_host]}:#{CONFIG[:ai_port]}/api/chat")
    @model   = CONFIG[:ai_model]
    @timeout = CONFIG[:ai_timeout]
  end

  def call(text, retries: CONFIG[:max_retries])
    attempts = 0

    begin
      attempts += 1
      body = build_request_body(text)
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
      messages: [{ role: "user", content: "Resuma de forma clara e objetiva:\n\n#{text}" }],
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

Pipeline.new.run
