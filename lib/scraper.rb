require 'httparty'
require 'nokogiri'
require_relative '../config'
require_relative 'network'

class Scraper
  def initialize(source)
    @source = source
  end

  def article_links
    LOGGER.info("Baixando página principal: #{@source[:name]}...")
    html = Network.get(@source[:base_url])
    doc  = Nokogiri::HTML(html)

    links = doc.css("a[href]")
               .map { |a| a["href"] }
               .map { |href| absolute_url(href) }
               .select { |href| article_link?(href) }
               .uniq

    LOGGER.info("Total de matérias encontradas em #{@source[:name]}: #{links.size}")
    links
  end

  def scrape_article(url)
    html = Network.get(url)
    doc  = Nokogiri::HTML(html)

    title    = doc.at_css("h1")&.text&.strip || "(sem título)"
    subtitle = subtitle(doc)

    paragraphs = doc.css(@source[:paragraph_selector])
                    .map { |p| p.text.strip }
                    .reject(&:empty?)
                    .uniq

    { source: @source[:name], url: url, title: title, subtitle: subtitle, paragraphs: paragraphs }
  end

  private

  def absolute_url(href)
    return "" if href.to_s.empty?
    return href if href.start_with?("http")

    "#{@source[:link_base_url]}#{href}"
  end

  def article_link?(href)
    href.match?(@source[:link_pattern]) && href.end_with?(@source[:link_suffix])
  end

  def subtitle(doc)
    selector = @source[:subtitle_selector]
    return nil unless selector

    doc.at_css(selector)&.text&.strip
  end
end
