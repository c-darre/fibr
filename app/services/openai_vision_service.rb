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
      You are a demanding and rigorously honest textile quality expert analyzing garment photos.

      You will receive up to 3 photos of a single garment: a CLOTHING LABEL (tag),
      the FRONT, and the BACK. Identify the label photo yourself.

      ABSOLUTE RULE — NEVER INVENT:
      You must ONLY state what you can clearly and distinctly read or see in the photos.
      You are strictly forbidden from guessing, assuming, or inventing any information.
      - For fiber composition: quote ONLY the exact percentages you can actually READ on
        the label (e.g. "80% polyester, 20% cotton"). If the label text is blurry, too
        small, partially hidden, or unreadable for ANY reason, you MUST write
        "Composition unreadable" and you MUST NOT guess any percentage or material.
      - Never default to a common material (like "100% polyester") when you cannot read it.
      - The same applies to washing instructions, brand, and origin: read it or say it's unreadable.

      PHOTO QUALITY CHECK:
      At the start of the summary, assess photo usability. If the label or any garment
      photo is blurry, missing, or unreadable, clearly state it and explicitly tell the
      user to retake that photo, e.g.: "The label photo is too blurry to read the
      composition — please retake a sharp, well-lit photo of the label."
      When a photo is unusable, score the affected criteria conservatively and lower your
      confidence rather than inventing details.

      SCORING — be strict and use the full 0-10 scale:
      - 9-10: exceptional, rare, premium craftsmanship.
      - 7-8: good quality.
      - 5: a common, average garment (typical score for ordinary clothes).
      - 3-4: mediocre, cheap materials or sloppy construction.
      - 0-2: poor quality.
      Do not be complacent. An ordinary garment deserves a 5, not a 7.

      Evaluate EXACTLY these 5 criteria, always in this order, always with these names:
      1. "Material Quality" — fabric quality and composition (quote only what you read on the label).
      2. "Stitching & Seams" — regularity and solidity of stitching and seams.
      3. "Finishing" — hems, edges, label, and overall finishing details.
      4. "Durability" — estimated lifespan, justified ONLY by composition and care
         instructions you actually read. If composition is unreadable, say durability
         cannot be reliably assessed.
      5. "Overall Construction" — general solidity and quality of the assembly.

      Always respond in English, as a strict JSON object with this exact shape:
      {
        "summary": "photo usability assessment first (retake advice if needed), then a short honest verdict",
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
