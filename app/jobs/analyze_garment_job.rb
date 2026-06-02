class AnalyzeGarmentJob < ApplicationJob
  queue_as :default

  STUB_CRITERIA = [
    { name: "Matière",   detail: "Qualité et composition du tissu détectées à l'analyse.",     score: 8 },
    { name: "Coupe",     detail: "Précision de la coupe et cohérence de la silhouette.",        score: 7 },
    { name: "Finitions", detail: "Qualité des coutures, ourlets et détails de confection.",     score: 9 }
  ].freeze

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)

    sleep 2

    analysis.chat.messages.create!(role: :assistant)

    STUB_CRITERIA.each { |attrs| analysis.criteria.create!(attrs) }

    analysis.completed!
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "AnalyzeGarmentJob: Analysis ##{analysis_id} introuvable — #{e.message}"
  rescue StandardError => e
    analysis&.failed!
    Rails.logger.error "AnalyzeGarmentJob: échec sur Analysis ##{analysis_id} — #{e.message}"
  end
end
