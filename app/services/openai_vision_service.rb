# app/services/openai_vision_service.rb
# Vrai appel à l'IA via GitHub Models (compatible API OpenAI).
# Même interface que StubVisionService : méthode call → renvoie le même Hash.
class OpenaiVisionService
  MODEL = "openai/gpt-4o"

  def initialize(analysis)
    @analysis = analysis
  end

  def call
    response = client.chat(
      parameters: {
        model: MODEL,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_content }
        ]
      }
    )

    raw = response.dig("choices", 0, "message", "content")
    cleaned = raw.gsub(/```json|```/, "").strip
    parsed = JSON.parse(cleaned)

    {
      content: parsed["summary"],
      score: parsed["score"],
      criteria: parsed["criteria"].map do |c|
        { name: c["name"], detail: c["detail"], score: c["score"] }
      end
    }
  end

  private

  def client
    @client ||= OpenAI::Client.new(
      access_token: ENV.fetch("OPENAI_API_KEY"),
      uri_base: "https://models.github.ai/inference"
    )
  end

  def system_prompt
    <<~PROMPT
      You are a textile quality expert analyzing garment photos.
      Always respond in English, as a strict JSON object with this exact shape:
      {
        "summary": "one short paragraph summarizing the overall quality",
        "score": <integer from 0 to 10>,
        "criteria": [
          { "name": "criterion name", "detail": "short explanation", "score": <integer 0 to 10> }
        ]
      }
      Provide between 3 and 5 criteria. Do not include any text outside the JSON.
    PROMPT
  end

  def user_content
    content = [{ type: "text", text: "Analyze the quality of this garment based on the photos." }]

    @analysis.chat.messages.each do |message|
      message.photos.each do |photo|
        base64 = Base64.strict_encode64(photo.download)
        content << {
          type: "image_url",
          image_url: { url: "data:#{photo.content_type};base64,#{base64}" }
        }
      end
    end

    content
  end
end
