class QuestionnaryJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)
    history = chat.messages.map { |m| { role: m.role, content: m.content } }

    llm = RubyLLM.chat(model: "claude-sonnet-4-6")
    llm.with_instructions(questionnary_prompt)
    response = llm.ask(history.to_json)
    cleaned = response.content.gsub(/```json|```/, "").strip
    parsed = JSON.parse(cleaned)

    chat.messages.create!(role: :assistant, content: parsed["message"])

    return unless parsed["complete"]

    run_ecobalyse(chat.analysis, parsed)
  end

  private

  def run_ecobalyse(analysis, parsed)
    fields = analysis.ecobalyse_fields || {}
    composition = fields["composition"] || []
    if composition.blank?
      analysis.questionnary_chat.messages.create!(role: :assistant,
                                                  content: "Impossible de calculer l'impact : la composition n'a pas pu être lue sur l'étiquette.")
      return
    end
    materials = EcobalyseService.build_materials(composition)
    product = parsed["product_type"] || fields["product_type"]
    mass = EcobalyseService.estimate_mass(product, parsed["size"])

    result = EcobalyseService.new(
      mass: mass,
      product: product,
      materials: materials
    ).call

    return if result[:error]

    analysis.update!(
      co2: result[:co2],
      water: result[:water],
      global_score: result[:global_score],
      garment_size: parsed["size"]
    )
  end

  def questionnary_prompt
    <<~PROMPT
      You ask the user for their garment's SIZE and confirm its TYPE, nothing else.
      Reply ONLY with strict JSON:
      {
        "message": "your question or confirmation to the user",
        "size": "XS|S|M|L|XL|XXL or null if unknown",
        "product_type": "tshirt|chemise|jean|pantalon|pull|jupe|manteau|calecon|chaussettes|maillot-de-bain|slip or null",
        "complete": true only when size AND product_type are known, else false
      }
      No text outside the JSON.
    PROMPT
  end
end
