require "ruby_llm/schema"
class GarmentAnalysisSchema < RubyLLM::Schema
  # --- Task 1: quality ---
  string  :summary, description: "Photo usability first, then a short honest verdict"
  integer :score,   description: "Overall quality score, integer 0-10"

  array :criteria, description: "Exactly 5 quality criteria, in the required order" do
    object do
      string  :name,   description: "Material Quality | Stitching & Seams | Finishing | Durability | Overall Construction"
      string  :detail, description: "Short justification"
      integer :score,  description: "Criterion score, integer 0-10"
    end
  end

  # --- Task 2: Ecobalyse extraction (NULLABLE = never invented) ---
  object :ecobalyse_fields do
    any_of :product_type, description: "Closest garment type; null only if none of these fits" do
      string enum: %w[tshirt chemise jean pantalon pull jupe manteau calecon chaussettes maillot-de-bain slip]
      null
    end

    any_of :composition, description: "Fibers read on the label, each {fiber, percentage}, percentages MUST sum to 100. IMPORTANT: if the label lists several layers (e.g. OUTER SHELL / INNER SHELL / LINING / PADDING), use ONLY the OUTER SHELL composition. If no layer distinction, use the main composition as-is. Set to null if the composition cannot be clearly read." do
      array do
        object do
          string  :fiber,      description: "English fiber name (cotton, polyester, wool, elastane, polyamide, viscose, linen...)"
          integer :percentage, description: "Percentage read on the label; the percentages sum to 100"
        end
      end
      null
    end

    any_of :country, description: "ISO 3166-1 alpha-2 from the 'Made in' label (FR, CN, BD, PT, TR...); null if not visible" do
      string
      null
    end

    any_of :construction, description: "'knitted' or 'woven'; null if you cannot tell" do
      string enum: %w[knitted woven]
      null
    end
  end
end
