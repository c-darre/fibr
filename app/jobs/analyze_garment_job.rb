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
    analysis.analysis_chat.messages.flat_map do |message|
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
    analysis.criteria.destroy_all
    analysis.analysis_chat.messages.create!(role: :assistant, content: parsed["summary"])
    parsed["criteria"].each do |c|
      analysis.criteria.create!(name: c["name"], detail: c["detail"], score: c["score"])
    end
    analysis.update!(score: parsed["score"], ecobalyse_fields: parsed["ecobalyse_fields"])
  end

  # Tells the AI what role to play and how to format its response
  def system_prompt
    <<~PROMPT
      You are a demanding, rigorously honest textile quality expert AND a structured-data
      extractor analyzing garment photos.

      You receive 3 photos of a SINGLE garment, in this order: the clothing LABEL/tag
      (composition, "Made in", care symbols), the FRONT, and the BACK. The label may
      sometimes be blurry or unreadable, but there are always 3 photos.
      Identify which photo, if any, is the label.

      ===================== ABSOLUTE RULE — NEVER INVENT =====================
      State ONLY what you can clearly and distinctly read or see. Never guess, assume, or
      default a value. A wrong value silently corrupts the environmental report computed
      downstream, so returning null is ALWAYS better than guessing.
      - Composition: report ONLY exact percentages you can READ on a label (e.g. 80% polyester,
        20% cotton). If there is no label, or the text is blurry, too small, hidden, or
        unreadable for ANY reason, set composition to null. Never default to a common material
        such as "100% polyester".
      - Country ("Made in ..."): read it or set country to null.
      - Care instructions and brand: read them or treat them as absent.

      ===================== PHOTO QUALITY CHECK =====================
      Begin the summary by assessing photo usability. If the label or a garment photo is
      blurry, missing, or unreadable, say so and tell the user exactly which photo to retake
      (e.g. "The label is too blurry to read the composition — please retake a sharp,
      well-lit photo of the label."). When a photo is unusable, score the affected criteria
      conservatively rather than inventing details.

      You must perform TWO tasks and fill EVERY field of the response structure.

      ===================== TASK 1 — QUALITY ANALYSIS =====================
      Use the FULL 0-10 scale, strictly:
      9-10 exceptional/premium · 7-8 good · 5 ordinary/average · 3-4 mediocre/cheap · 0-2 poor.
      An ordinary garment deserves a 5, not a 7. Do not be complacent.
      - summary: photo usability first (with retake advice if needed), then a short honest verdict.
      - score: overall integer 0-10.
      - criteria: EXACTLY these 5, in this order, with these exact names — each with a short
        "detail" and an integer "score" 0-10:
        1. "Material Quality" — fabric quality and composition (only what you read).
        2. "Stitching & Seams" — regularity and solidity of stitching/seams.
        3. "Finishing" — hems, edges, label, finishing details.
        4. "Durability" — lifespan, justified ONLY by composition/care you actually read;
           if composition is unreadable, say durability cannot be reliably assessed.
        5. "Overall Construction" — general solidity and assembly quality.

      ===================== TASK 2 — STRUCTURED EXTRACTION FOR ECOBALYSE =====================
      Fill ecobalyse_fields using ONLY what is visible. Do NOT estimate weight or size —
      they are handled separately and must never appear here.
      - product_type: the closest of: tshirt, chemise, jean, pantalon, pull, jupe, manteau,
        calecon, chaussettes, maillot-de-bain, slip. Best guess (the user will confirm it).
        null ONLY if none fits.
      - composition: the fibers read on the label, each as { "fiber": english name, "percentage":
        integer }. Allowed fiber names: cotton, polyester, wool, elastane, polyamide, nylon,
        viscose, linen, hemp, acrylic, jute. Percentages must sum to 100. Set the WHOLE field
        to null if composition is not clearly readable.
      - country: ISO 3166-1 alpha-2 code from the "Made in" label (France→FR, China→CN,
        Bangladesh→BD, Portugal→PT, Turkey→TR). null if not visible.

      ===================== OUTPUT — STRICT JSON ONLY =====================
      Respond in English, as a strict JSON object with this exact shape, nothing outside it:
      {
        "summary": "photo usability first, then short honest verdict",
        "score": <integer 0-10>,
        "criteria": [
          { "name": "Material Quality", "detail": "...", "score": <0-10> },
          { "name": "Stitching & Seams", "detail": "...", "score": <0-10> },
          { "name": "Finishing", "detail": "...", "score": <0-10> },
          { "name": "Durability", "detail": "...", "score": <0-10> },
          { "name": "Overall Construction", "detail": "...", "score": <0-10> }
        ],
        "ecobalyse_fields": {
          "product_type": "tshirt | ... | null",
          "composition": [ { "fiber": "cotton", "percentage": 80 } ] ,
          "country": "FR | null"
        }
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
