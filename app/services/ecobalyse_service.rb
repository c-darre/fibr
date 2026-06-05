# app/services/ecobalyse_service.rb
# Appelle l'API Ecobalyse (gouvernementale) pour calculer l'impact
# environnemental d'un vêtement. Renvoie un Hash propre avec les impacts clés.
class EcobalyseService
  API_URL = "https://ecobalyse.beta.gouv.fr/api/textile/simulator"

  # Correspondance entre les noms de fibres renvoyés par l'IA (en anglais)
  # et les UUID des matières Ecobalyse (variantes conventionnelles par défaut).
  MATERIAL_UUIDS = {
    "cotton"    => "62a4d6fb-3276-4ba5-93a3-889ecd3bff84", # Coton
    "polyester" => "9dba0e95-0c35-4f8b-9267-62ddf47d4984", # Polyester
    "wool"      => "1fc3e17d-5661-429d-a150-7986eae16d9d", # Laine par défaut
    "elastane"  => "9973088b-c929-4cc5-894a-1e4d28c161d4", # Elasthane
    "polyamide" => "c84280ff-e921-4d5c-92d6-51030bf4f74e", # Nylon
    "nylon"     => "c84280ff-e921-4d5c-92d6-51030bf4f74e", # Nylon (synonyme)
    "viscose"   => "c087d394-5901-4b03-ba7a-7d4b0db0490c", # Viscose
    "linen"     => "a52e486c-b67e-40af-8337-e8143cbf9076", # Lin
    "hemp"      => "0c1a4654-b030-4fe1-86b7-d96ce0b85bb8", # Chanvre
    "acrylic"   => "49a0bec0-f9f3-42db-a514-a9dcf06a8969", # Acrylique
    "jute"      => "a09b2677-2900-4417-a202-e5f9a1abcce1"  # Jute
  }.freeze

  # Convertit la composition de l'IA [{ "fiber" => "cotton", "percentage" => 80 }, ...]
  # vers le format Ecobalyse [{ id: "uuid", share: 0.8 }, ...]
  def self.build_materials(composition)
    composition.filter_map do |item|
      uuid = MATERIAL_UUIDS[item["fiber"].to_s.downcase]
      next unless uuid # ignore une fibre inconnue plutôt que de planter

      { id: uuid, share: item["percentage"].to_f / 100.0 }
    end
  end
  # Poids de base (kg) par type, taille M de référence
  BASE_WEIGHTS = {
    "tshirt" => 0.15, "chemise" => 0.2, "jean" => 0.6, "pantalon" => 0.45,
    "pull" => 0.4, "jupe" => 0.3, "manteau" => 1.2, "calecon" => 0.08,
    "chaussettes" => 0.05, "maillot-de-bain" => 0.15, "slip" => 0.06
  }.freeze

  SIZE_COEFFICIENTS = {
    "XS" => 0.8, "S" => 0.9, "M" => 1.0, "L" => 1.15, "XL" => 1.3, "XXL" => 1.45
  }.freeze

  def self.estimate_mass(product, size)
    base = BASE_WEIGHTS[product.to_s.downcase] || 0.3
    coef = SIZE_COEFFICIENTS[size.to_s.upcase] || 1.0
    (base * coef).round(3)
  end

  def initialize(mass:, product:, materials:)
    @mass = mass            # poids en kg (ex: 0.17)
    @product = product      # type (ex: "tshirt")
    @materials = materials  # liste de matières [{ id:, share: }]
  end

  def call
    response = post_request

    return { error: "Ecobalyse error #{response.code}" } unless response.code == "200"

    data = JSON.parse(response.body)
    impacts = data["impacts"] || {}

    {
      co2: impacts["cch"],        # kg équivalent CO2
      water: impacts["wtu"],      # consommation d'eau
      global_score: impacts["ecs"], # score d'impact global
      web_url: data["webUrl"]     # lien vers le détail Ecobalyse
    }
  rescue StandardError => e
    Rails.logger.error "EcobalyseService error: #{e.message}"
    { error: e.message }
  end

  private

  def post_request
    require "net/http"
    require "json"

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["token"] = ENV.fetch("ECOBALYSE_TOKEN")
    request.body = {
      mass: @mass,
      product: @product,
      materials: @materials
    }.to_json

    http.request(request)
  end
end
