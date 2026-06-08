class DiscussionJob < ApplicationJob
  queue_as :default

  def perform(chat_id)
    chat     = Chat.find(chat_id)
    analysis = chat.analysis
    reply    = ask_ai(chat, analysis)
    chat.messages.create!(role: :assistant, content: reply)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "DiscussionJob: Chat ##{chat_id} not found — #{e.message}"
  rescue StandardError => e
    Rails.logger.error "DiscussionJob: failed for Chat ##{chat_id} — #{e.message}"
  end

  private

  def stub_result
    sleep 2
    "This garment shows solid construction with regular stitching. " \
      "The composition on the label suggests good durability. " \
      "Feel free to ask me any questions about the analyzed criteria."
  end

  def ask_ai(chat, analysis)
    return stub_result unless ENV["VISION_SERVICE"] == "real"

    messages = chat.messages.where.not(content: [nil, ""]).order(:created_at)
    llm_chat = RubyLLM.chat(model: "claude-sonnet-4-6")
    llm_chat.with_instructions(system_prompt(analysis))
    response = llm_chat.ask(build_user_message(messages))
    response.content
  end

  def build_user_message(messages)
    history = messages.map { |m| "#{m.role.upcase}: #{m.content}" }.join("\n")
    "Conversation so far:\n#{history}\n\nPlease answer the last USER message."
  end

  def system_prompt(analysis)
    <<~PROMPT
      You are a textile expert working for Fibr, a garment quality analysis application.

      You have access to the results of the user's garment analysis.
      Your role is to answer their questions to help them better understand these results.

      ABSOLUTE RULES:
      - You NEVER assign new scores or ratings.
      - You NEVER question existing scores.
      - You ONLY explain what has already been analyzed.

      You can explain: materials and their environmental impact, care instructions,
      traceability, durability, and why a given criterion received a particular score.

      Be educational, honest, and concise. Always reply in the user's language.

      #{analysis_context(analysis)}
    PROMPT
  end

  def analysis_context(analysis)
    summary = analysis.analysis_chat.messages.find_by(role: :assistant)&.content
    criteria_text = analysis.criteria.map { |c| "- #{c.name}: #{c.score}/10 — #{c.detail}" }.join("\n")

    "ANALYSIS RESULTS:\nOverall score: #{analysis.score}/10\nSummary: #{summary}\n\nCriteria:\n#{criteria_text}"
  end
end
