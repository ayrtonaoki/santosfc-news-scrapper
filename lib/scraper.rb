require 'httparty'
require 'nokogiri'
require_relative '../config'
require_relative 'network'

class Scraper
  def initialize(base_url)
    @base_url = base_url
  end

  def article_links
    LOGGER.info("Baixando página principal...")
    html = Network.get(@base_url)
    doc  = Nokogiri::HTML(html)

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
