# app/jobs/analyze_garment_job.rb
# Runs in the background after the user uploads photos.
# Calls the AI (or a stub) and saves the result to the database.
class AnalyzeGarmentJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    parsed   = ask_ai(analysis)
    save_results(analysis, parsed)
    analysis.completed!
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "AnalyzeGarmentJob: Analysis ##{analysis_id} not found — #{e.message}"
  rescue StandardError => e
    analysis&.failed!
    Rails.logger.error "AnalyzeGarmentJob: failed for Analysis ##{analysis_id} — #{e.message}"
  end

  private

  # Returns a fake result instantly — set VISION_SERVICE=real in .env to use the real AI
  def stub_result
    sleep 2 # simulates AI "thinking" so you can see the loading screen
    {
      "summary" => "Simulated analysis: good quality fabric, regular stitching, clean finishing.",
      "score" => 8,
      "criteria" => [
        { "name" => "Material Quality",     "detail" => "Fabric feels sturdy and well-composed.",     "score" => 8 },
        { "name" => "Stitching & Seams",    "detail" => "Regular, tight stitching throughout.",       "score" => 7 },
        { "name" => "Finishing",            "detail" => "Clean hems, neat label, no loose threads.",  "score" => 9 },
        { "name" => "Durability",           "detail" => "Should last several years with normal use.", "score" => 7 },
        { "name" => "Overall Construction", "detail" => "Well-assembled garment overall.",            "score" => 8 }
      ]
    }
  end

  # Calls the AI with the uploaded photos and returns the parsed JSON hash
  def ask_ai(analysis)
    return stub_result unless ENV["VISION_SERVICE"] == "real"

    images   = build_images(analysis)
    chat     = RubyLLM.chat(model: "gpt-4o")
    chat.with_instructions(system_prompt)
    response = chat.ask(user_message, with: { images: images })
    cleaned  = response.content.gsub(/```json|```/, "").strip
    JSON.parse(cleaned)
  ensure
    cleanup_tempfiles # always delete temp files, even if the AI call fails
  end

  # Collects temp file paths for all photos attached to this analysis
  def build_images(analysis)
    @tempfiles = []
    analysis.chat.messages.flat_map do |message|
      message.photos.map { |photo| photo_to_tempfile(photo) }
    end
  end

  # Downloads one photo to a temp file and returns its path.
  # RubyLLM reads images from disk — it does not accept base64 data URIs.
  def photo_to_tempfile(photo)
    ext = File.extname(photo.filename.to_s)
    tmp = Tempfile.new(["fibr_photo", ext])
    tmp.binmode
    tmp.write(photo.download)
    tmp.rewind
    @tempfiles << tmp # keep a reference so Ruby's GC doesn't delete it early
    tmp.path
  end

  def cleanup_tempfiles
    @tempfiles&.each(&:close!)
  end

  # Saves the AI summary, overall score, and 5 criteria to the database
  def save_results(analysis, parsed)
    analysis.chat.messages.create!(role: :assistant, content: parsed["summary"])
    parsed["criteria"].each do |c|
      analysis.criteria.create!(name: c["name"], detail: c["detail"], score: c["score"])
    end
    analysis.update!(score: parsed["score"])
  end

  # Tells the AI what role to play and how to format its response
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

  # The message sent to the AI alongside the photos
  def user_message
    "Here are the photos of one garment (clothing label, front, and back). " \
      "Identify the label and read all useful information on it, then analyze " \
      "the garment quality according to your instructions."
  end
end
