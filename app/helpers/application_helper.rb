module ApplicationHelper
  def render_markdown(text)
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true)
    markdown.render(text.to_s)
  end
end
