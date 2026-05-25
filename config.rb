require 'dotenv/load'
require 'logger'

CONFIG = {
  sources:        [
    {
      name: "GE",
      base_url: "https://ge.globo.com/sp/santos-e-regiao/futebol/times/santos/",
      link_pattern: %r{/sp/santos-e-regiao/futebol/times/santos/noticia/},
      link_suffix: ".ghtml",
      link_base_url: "https://ge.globo.com",
      subtitle_selector: ".content-head__subtitle",
      paragraph_selector: ".mc-article-body p, article p"
    },
    {
      name: "Diário do Peixe",
      base_url: "https://www.diariodopeixe.com.br/",
      link_pattern: %r{^https://www\.diariodopeixe\.com\.br/noticias/.+},
      link_suffix: "/",
      link_base_url: "https://www.diariodopeixe.com.br",
      subtitle_selector: nil,
      paragraph_selector: ".post-content p, .fusion-post-content p, article p"
    }
  ],
  ai_model:       ENV.fetch("AI_MODEL", "llama3"),
  ai_host:        ENV.fetch("AI_HOST", "localhost"),
  ai_port:        ENV.fetch("AI_PORT", "11434").to_i,
  ai_timeout:     300,
  max_chars:      6_000,
  max_retries:    3,
  retry_delay:    2,
  max_articles:   ENV.fetch("MAX_ARTICLES", "2").to_i,
  summary_prompt: ENV.fetch("SUMMARY_PROMPT", "Resuma de forma clara e objetiva:\n\n%s"),
  output_file:    ENV.fetch("OUTPUT_FILE", "/tmp/noticias-#{Time.now.strftime('%d-%m-%Y')}.txt"),
  notion_token:   ENV.fetch("NOTION_TOKEN")   { raise "Variável de ambiente NOTION_TOKEN não definida" },
  notion_page_id: ENV.fetch("NOTION_PAGE_ID") { raise "Variável de ambiente NOTION_PAGE_ID não definida" },
  notify:         ENV.fetch("NOTIFY", "notion").split(",").map(&:to_sym)
}.freeze

SEPARATOR = "=" * 90

LOGGER = Logger.new($stdout).tap do |l|
  l.formatter = proc { |_severity, _datetime, _progname, msg|
    "[#{Time.now.strftime('%H:%M:%S')}] #{msg}\n"
  }
  l.level = Logger::INFO
end
