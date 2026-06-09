module ApplicationHelper
  def markdown(text)
    renderer = Redcarpet::Render::HTML.new(
      no_images: true,
      no_styles: true,
      safe_links_only: true
    )
    md = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      no_intra_emphasis: true
    )
    md.render(text.to_s).html_safe
  end
end
