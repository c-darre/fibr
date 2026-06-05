class QuestionnaryJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat = Chat.find(chat_id)
    history = chat.messages.map { |m| { role: m.role, content: m.content } }

    llm = RubyLLM.chat(model: "gpt-4o")
    llm.with_instructions(questionnary_prompt)
    response = llm.ask(history.to_json)
    cleaned = response.content.gsub(/```json|```/, "").strip
    parsed = JSON.parse(cleaned)

    chat.messages.create!(role: :assistant, content: parsed["message"])

    if parsed["complete"]
      run_ecobalyse(chat.analysis, parsed)
    end
  end

  private

  def run_ecobalyse(analysis, parsed)
    # composition vient de l'analyse qualité (à récupérer selon ce que le collègue stocke)
    composition = [] # TODO: brancher sur la vraie composition
    materials = EcobalyseService.build_materials(composition)
    mass = EcobalyseService.estimate_mass(parsed["product_type"], parsed["size"])

    result = EcobalyseService.new(
      mass: mass,
      product: parsed["product_type"],
      materials: materials
    ).call

    # TODO: stocker result (co2, water, global_score) — besoin migration
    Rails.logger.info "Ecobalyse: #{result.inspect}"
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
