require 'dotenv/load'
require 'httparty'
require 'nokogiri'
require 'net/http'
require 'json'
require 'logger'

CONFIG = {
  base_url:     "https://ge.globo.com/sp/santos-e-regiao/futebol/times/santos/",
  ai_model:     ENV.fetch("AI_MODEL", "llama3"),
  ai_host:      ENV.fetch("AI_HOST", "localhost"),
  ai_port:      ENV.fetch("AI_PORT", "11434").to_i,
  ai_timeout:   300,
  max_chars:    6_000,
  max_retries:  3,
  retry_delay:  2,
  max_articles: ENV.fetch("MAX_ARTICLES", "2").to_i,
  summary_prompt: ENV.fetch("SUMMARY_PROMPT", "Resuma de forma clara e objetiva:\n\n%s"),
  output_file:  ENV.fetch("OUTPUT_FILE", "/tmp/noticias-#{Time.now.strftime('%d-%m-%Y')}.txt"),
  notion_token:   ENV.fetch("NOTION_TOKEN")   { raise "Variável de ambiente NOTION_TOKEN não definida" },
  notion_page_id: ENV.fetch("NOTION_PAGE_ID") { raise "Variável de ambiente NOTION_PAGE_ID não definida" },
  notify:       ENV.fetch("NOTIFY", "notion").split(",").map(&:to_sym)
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
    LOGGER.info(SEPARATOR)
    LOGGER.info(data[:title].upcase)
    LOGGER.info(data[:subtitle].to_s)
    LOGGER.info(data[:summary])
  end

  def self.save_to_txt(results, path: CONFIG[:output_file])
    content = results.map do |data|
      <<~BLOCK
        #{SEPARATOR}

        #{data[:title].upcase}
        #{data[:subtitle]}
        #{data[:summary]}
      BLOCK
    end.join("\n")

    File.write(path, content)
    LOGGER.info("Resultados salvos em: #{path}")
  end

  def self.save_to_notion(results)
    children = results.flat_map do |data|
      [
        {
          object: "block",
          type: "heading_2",
          heading_2: {
            rich_text: [{ type: "text", text: { content: data[:title] }, annotations: { bold: true } }]
          }
        },
        {
          object: "block",
          type: "paragraph",
          paragraph: {
            rich_text: [{ type: "text", text: { content: data[:subtitle].to_s }, annotations: { italic: true, color: "gray" } }]
          }
        },
        {
          object: "block",
          type: "paragraph",
          paragraph: {
            rich_text: [{ type: "text", text: { content: "Resumo" }, annotations: { bold: true } }]
          }
        },
        *data[:summary].chars.each_slice(2000).map(&:join).map do |chunk|
          {
            object: "block",
            type: "paragraph",
            paragraph: { rich_text: [{ type: "text", text: { content: chunk } }] }
          }
        end,
        { object: "block", type: "divider", divider: {} }
      ]
    end

    response = HTTParty.post(
      "https://api.notion.com/v1/pages",
      headers: {
        "Authorization"  => "Bearer #{CONFIG[:notion_token]}",
        "Notion-Version" => "2022-06-28",
        "Content-Type"   => "application/json"
      },
      body: {
        parent: { page_id: CONFIG[:notion_page_id] },
        properties: {
          title: {
            title: [{ text: { content: "Notícias Santos - #{Time.now.strftime('%d-%m-%Y')}" } }]
          }
        },
        children: children
      }.to_json
    )

    LOGGER.info("Notion status: #{response.code}")
    LOGGER.info("Salvo no Notion!") if response.code == 200
    LOGGER.error("Notion error: #{response.body}") unless response.code == 200
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

    links.first(CONFIG[:max_articles]).each do |link|
      result = process_article(link)
      next unless result

      @results << result
      Reporter.print_article(result)
    end

    LOGGER.info(SEPARATOR)
    LOGGER.info("Script finalizado! #{@results.size}/#{links.size} matérias processadas.")

    return if @results.empty?

    Reporter.save_to_txt(@results)    if CONFIG[:notify].include?(:txt)
    Reporter.save_to_notion(@results) if CONFIG[:notify].include?(:notion)
  end

  private

  def process_article(link)
    article = scrape_safely(link)
    return unless article

    summary = summarize_safely(article)
    return unless summary

    article.merge(summary: summary)
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

    title    = doc.at_css("h1")&.text&.strip || "(sem título)"
    subtitle = doc.at_css(".content-head__subtitle")&.text&.strip

    # Seletor com fallback — .mc-article-body é específico do GE e pode mudar
    paragraphs = doc.css(".mc-article-body p, article p")
                    .map { |p| p.text.strip }
                    .reject(&:empty?)
                    .uniq

    { url: url, title: title, subtitle: subtitle, paragraphs: paragraphs }
  end
end

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

Pipeline.new.run
