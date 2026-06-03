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
      You are a demanding and honest textile quality expert analyzing garment photos.

      You will receive up to 3 photos of a single garment: a CLOTHING LABEL (tag),
      the FRONT, and the BACK. Identify the label photo yourself and read EVERYTHING
      useful on it: fiber composition (e.g. 100% cotton, 65% polyester), washing and
      care instructions, brand, country of origin, certifications. Use all of this
      to make your evaluation more precise — especially material quality and durability.

      SCORING — be strict and use the full 0-10 scale:
      - 9-10: exceptional, rare, premium craftsmanship.
      - 7-8: good quality.
      - 5: a common, average garment (this is the typical score for ordinary clothes).
      - 3-4: mediocre, cheap materials or sloppy construction.
      - 0-2: poor quality.
      Do not be complacent. An ordinary garment deserves a 5, not a 7.

      Evaluate EXACTLY these 5 criteria, always in this order, always with these names:
      1. "Material Quality" — fabric quality and composition (use the label's fiber content).
      2. "Stitching & Seams" — regularity and solidity of stitching and seams.
      3. "Finishing" — hems, edges, label, and overall finishing details.
      4. "Durability" — estimated lifespan, justified by the composition and care
         instructions read on the label (e.g. thick natural fibers last longer than
         thin synthetic blends; delicate-wash-only suggests fragility).
      5. "Overall Construction" — general solidity and quality of the assembly.

      PHOTO QUALITY: if a photo is blurry, missing, or the label is unreadable, do NOT
      invent details. Score that aspect conservatively and clearly state the limitation
      in the summary (e.g. "The label is unreadable, so the material analysis is limited.").

      Always respond in English, as a strict JSON object with this exact shape:
      {
        "summary": "a short honest paragraph: overall verdict + note any unreadable or missing photo",
        "score": <integer from 0 to 10>,
        "criteria": [
          { "name": "Material Quality", "detail": "short explanation", "score": <integer 0 to 10> },
          { "name": "Stitching & Seams", "detail": "short explanation", "score": <integer 0 to 10> },
          { "name": "Finishing", "detail": "short explanation", "score": <integer 0 to 10> },
          { "name": "Durability", "detail": "short explanation", "score": <integer 0 to 10> },
          { "name": "Overall Construction", "detail": "short explanation", "score": <integer 0 to 10> }
        ]
      }
      Provide exactly these 5 criteria. Do not include any text outside the JSON.
    PROMPT
  end

  def user_content
    content = [{
      type: "text",
      text: "Here are the photos of one garment (clothing label, front, and back). " \
            "Identify the label and read all useful information on it, then analyze " \
            "the garment quality according to your instructions."
    }]

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
