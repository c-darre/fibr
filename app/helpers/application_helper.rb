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

  def meta_title
    content_for?(:meta_title) ? content_for(:meta_title) : DEFAULT_META["meta_title"]
  end

  def meta_description
    content_for?(:meta_description) ? content_for(:meta_description) : DEFAULT_META["meta_description"]
  end

  def meta_image
    # meta_image = (content_for?(:meta_image) ? content_for(:meta_image) : DEFAULT_META["meta_image"])
    # # Permet de gérer les URLs absolues ou les images locales
    # meta_image.starts_with?("http") ? meta_image : image_url(meta_image)
  end
end
