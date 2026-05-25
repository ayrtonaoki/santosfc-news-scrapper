require_relative '../config'
require_relative 'scraper'
require_relative 'summarizer'
require_relative 'truncator'
require_relative 'reporter'

class Pipeline
  def initialize
    @summarizer = Summarizer.new
    @results    = []
  end

  def run
    LOGGER.info("Iniciando...")

    CONFIG[:sources].each do |source|
      scraper = Scraper.new(source)
      links = scraper.article_links

      links.first(CONFIG[:max_articles]).each do |link|
        result = process_article(scraper, link)
        next unless result

        @results << result
        Reporter.print_article(result)
      end

      LOGGER.info("#{source[:name]}: #{@results.count { |result| result[:source] == source[:name] }}/#{links.size} matérias processadas.")
    end

    LOGGER.info(SEPARATOR)
    LOGGER.info("Script finalizado! #{@results.size} matérias processadas.")

    return if @results.empty?

    Reporter.save_to_txt(@results)    if CONFIG[:notify].include?(:txt)
    Reporter.save_to_notion(@results) if CONFIG[:notify].include?(:notion)
  end

  private

  def process_article(scraper, link)
    article = scrape_safely(scraper, link)
    return unless article

    summary = summarize_safely(article)
    return unless summary

    article.merge(summary: summary)
  rescue StandardError => e
    LOGGER.error("Erro inesperado em #{link}: #{e.message}")
    nil
  end

  def scrape_safely(scraper, link)
    scraper.scrape_article(link)
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
