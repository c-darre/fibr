# app/jobs/analyze_garment_job.rb
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

  def stub_result
    sleep 2
    {
      "garment_type" => "T-shirt",
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

  # Calls the AI with the uploaded photos and a STRUCTURED SCHEMA.
  # The schema forces a fixed response shape → far more reliable than parsing free JSON.
  def ask_ai(analysis)
    return stub_result unless ENV["VISION_SERVICE"] == "real"

    images   = build_images(analysis)
    chat     = RubyLLM.chat(model: "claude-sonnet-4-6")
    chat.with_instructions(system_prompt)
    chat.with_schema(GarmentAnalysisSchema)
    response = chat.ask(user_message, with: { images: images })

    # With a schema, response.content is already a structured Hash.
    # We still handle the case where it might come back as a JSON string.
    data = response.content
    data = JSON.parse(data) if data.is_a?(String)

    # The schema doesn't include garment_type, so we keep it from product_type if needed
    data["garment_type"] ||= data.dig("ecobalyse_fields", "product_type")
    data
  ensure
    cleanup_tempfiles
  end

  def build_images(analysis)
    @tempfiles = []
    analysis.analysis_chat.messages.flat_map do |message|
      message.photos.map { |photo| photo_to_tempfile(photo) }
    end
  end

  def photo_to_tempfile(photo)
    ext = File.extname(photo.filename.to_s)
    tmp = Tempfile.new(["fibr_photo", ext])
    tmp.binmode
    tmp.write(photo.download)
    tmp.rewind
    @tempfiles << tmp
    tmp.path
  end

  def cleanup_tempfiles
    @tempfiles&.each(&:close!)
  end

  def save_results(analysis, parsed)
    analysis.criteria.destroy_all
    analysis.analysis_chat.messages.create!(role: :assistant, content: parsed["summary"])
    parsed["criteria"].each do |c|
      analysis.criteria.create!(name: c["name"], detail: c["detail"], score: c["score"])
    end
    analysis.update!(score: parsed["score"], garment_type: parsed["garment_type"], ecobalyse_fields: parsed["ecobalyse_fields"])
  end

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
      - Composition: report ONLY exact percentages you can READ on a label. If there is no
        label, or the text is blurry, too small, hidden, or unreadable for ANY reason, set
        composition to null. Never default to a common material such as "100% polyester".
      - Country ("Made in ..."): read it or set country to null.
      - Care instructions and brand: read them or treat them as absent.

      ===================== MULTI-LAYER LABELS (IMPORTANT) =====================
      Many garments (jackets, coats, padded items) list SEVERAL layers, e.g.:
        OUTER SHELL: 100% cotton / INNER SHELL: 100% polyamide / PADDING: 100% polyester.
      In that case, use ONLY the OUTER SHELL (outer fabric) composition for the composition
      field. Ignore lining and padding for the composition. The label may repeat the same
      info in several languages (EN/FR/DE/IT) — read the ENGLISH version. This rule makes the
      extraction deterministic: always pick the outer shell.

      ===================== PHOTO QUALITY CHECK =====================
      Begin the summary by assessing photo usability. If the label or a garment photo is
      blurry, missing, or unreadable, say so and tell the user exactly which photo to retake.
      When a photo is unusable, score the affected criteria conservatively rather than inventing.

      ===================== TASK 1 — QUALITY ANALYSIS =====================
      Use the FULL 0-10 scale, strictly:
      9-10 exceptional/premium · 7-8 good · 5 ordinary/average · 3-4 mediocre/cheap · 0-2 poor.
      An ordinary garment deserves a 5, not a 7. Do not be complacent.
      - summary: photo usability first (with retake advice if needed), then a short honest verdict.
      - score: overall integer 0-10.
      - criteria: EXACTLY these 5, in this order, with these exact names:
        Material Quality, Stitching & Seams, Finishing, Durability, Overall Construction.

      ===================== TASK 2 — STRUCTURED EXTRACTION FOR ECOBALYSE =====================
      Fill ecobalyse_fields using ONLY what is visible. Do NOT estimate weight or size.
      - product_type: closest of the allowed types. Best guess (the user will confirm). null only if none fits.
      - composition: outer shell fibers (see multi-layer rule), each {fiber, percentage}, summing to 100.
        Allowed fibers: cotton, polyester, wool, elastane, polyamide, nylon, viscose, linen, hemp, acrylic, jute.
        null if not clearly readable.
      - country: ISO 3166-1 alpha-2 from "Made in". null if not visible.
      - construction: knitted or woven, null if unsure.

      Respond strictly according to the provided schema. Reply in English.
    PROMPT
  end

  def user_message
    "Here are the photos of one garment (clothing label, front, and back). " \
      "Identify the label and read all useful information on it, then analyze " \
      "the garment quality according to your instructions."
  end
end
