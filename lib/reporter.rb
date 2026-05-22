require 'httparty'
require_relative '../config'

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
