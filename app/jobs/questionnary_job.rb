class QuestionnaryJob < ApplicationJob
  queue_as :default

  SIZE_LETTER_PATTERN = /\b(XXL|XL|XS|[SML])\b/i
  SIZE_NUMBER_PATTERN = /\b([2-4]\d)\b/

  def perform(chat_id)
    chat = Chat.find(chat_id)
    analysis = chat.analysis

    return if analysis.co2.present?

    known_type = analysis.ecobalyse_fields&.dig("product_type")

    last_user_content = chat.messages.where(role: :user).order(:created_at).last&.content.to_s
    size = last_user_content[SIZE_LETTER_PATTERN, 1]&.upcase
    size ||= last_user_content[SIZE_NUMBER_PATTERN, 1]

    if size.nil?
      chat.messages.create!(
        role: :assistant,
        content: "Bonjour ! Quelle est la taille de votre #{known_type || 'vêtement'} ? (XS, S, M, L, XL ou XXL)"
      )
      return
    end

    composition = analysis.ecobalyse_fields&.dig("composition") || []
    if composition.blank?
      chat.messages.create!(
        role: :assistant,
        content: "Impossible de calculer l'impact : composition illisible."
      )
      return
    end

    result = EcobalyseService.new(
      mass: EcobalyseService.estimate_mass(known_type, letter_size(size)),
      product: known_type,
      materials: EcobalyseService.build_materials(composition)
    ).call

    Rails.logger.info("ECOBALYSE RESULT -> #{result.inspect}")

    if result[:error]
      chat.messages.create!(role: :assistant, content: "Une erreur est survenue lors du calcul de l'impact.")
      return
    end

    analysis.update!(
      co2: result[:co2],
      water: result[:water],
      global_score: result[:global_score],
      garment_size: size
    )

    chat.messages.create!(
      role: :assistant,
      content: "Parfait, taille #{size} notée ! Voir le résultat : #{Rails.application.routes.url_helpers.analysis_path(analysis)}"
    )
  end

  private

  def letter_size(size)
    return size unless size.match?(/\A\d+\z/)

    case size.to_i
    when ..28    then "XS"
    when 29..30  then "S"
    when 31..33  then "M"
    when 34..36  then "L"
    when 37..40  then "XL"
    else              "XXL"
    end
  end
end
