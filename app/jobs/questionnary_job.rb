class QuestionnaryJob < ApplicationJob
  queue_as :default

  SIZE_LETTER_PATTERN = /\b(XXL|XL|XS|[SML])\b/i
  SIZE_NUMBER_PATTERN = /\b([2-4]\d)\b/

  PRODUCT_TYPE_LABELS = {
    "tshirt"          => "t-shirt",
    "chemise"         => "shirt",
    "jean"            => "jeans",
    "pantalon"        => "trousers",
    "pull"            => "sweater",
    "jupe"            => "skirt",
    "manteau"         => "coat",
    "calecon"         => "boxer shorts",
    "chaussettes"     => "socks",
    "maillot-de-bain" => "swimsuit",
    "slip"            => "briefs"
  }

  def perform(chat_id)
    chat = Chat.find(chat_id)
    analysis = chat.analysis

    return if analysis.co2.present?

    # Clé Ecobalyse (ex. "manteau") → c'est CE qu'on envoie à l'API
    product_type = analysis.ecobalyse_fields&.dig("product_type")
    # Libellé anglais (ex. "coat") → UNIQUEMENT pour le message affiché à l'utilisateur
    known_type = PRODUCT_TYPE_LABELS[product_type]

    last_user_content = chat.messages.where(role: :user).order(:created_at).last&.content.to_s
    size = last_user_content[SIZE_LETTER_PATTERN, 1]&.upcase
    size ||= last_user_content[SIZE_NUMBER_PATTERN, 1]

    if size.nil?
      message = chat.messages.create!(
        role: :assistant,
        content: "Hello! What is the size of your #{known_type || 'garment'}? (XS, S, M, L, XL or XXL)"
      )
      # Replace the typing indicator with the new assistant message
      broadcast_message(chat, message)
      return
    end

    composition = analysis.ecobalyse_fields&.dig("composition") || []
    if composition.blank?
      message = chat.messages.create!(
        role: :assistant,
        content: "Unable to calculate impact: unreadable composition."
      )
      # Replace the typing indicator with the error message
      broadcast_message(chat, message)
      return
    end

    result = EcobalyseService.new(
      mass: EcobalyseService.estimate_mass(product_type, letter_size(size)),
      product: product_type,
      materials: EcobalyseService.build_materials(composition)
    ).call

    Rails.logger.info("ECOBALYSE RESULT -> #{result.inspect}")

    if result[:error]
      message = chat.messages.create!(role: :assistant, content: "An error occurred while calculating the impact.")
      # Replace the typing indicator with the error message
      broadcast_message(chat, message)
      return
    end

    analysis.update!(
      co2: result[:co2],
      water: result[:water],
      global_score: result[:global_score],
      garment_size: size
    )

    message = chat.messages.create!(
      role: :assistant,
      content: "Perfect, size #{size} noted! Click the button below to see your environmental impact results."
    )
    # Replace the typing indicator with the confirmation message
    broadcast_message(chat, message)

    # Désactive la zone de saisie : on la remplace par un bouton vers les résultats
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{chat.id}",
      target: "quiz-input-zone",
      partial: "analyses/quiz_done",
      locals: { analysis: analysis }
    )
  end

  private

  # Replaces the typing indicator in the chat view with a new assistant message bubble
  def broadcast_message(chat, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{chat.id}",
      target: "typing-indicator",
      partial: "messages/message",
      locals: { message: message }
    )
  end

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
