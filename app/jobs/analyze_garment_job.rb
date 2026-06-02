# app/jobs/analyze_garment_job.rb
class AnalyzeGarmentJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)

    result = vision_service.new(analysis).call

    analysis.chat.messages.create!(role: :assistant, content: result[:content])
    result[:criteria].each { |attrs| analysis.criteria.create!(attrs) }
    analysis.update!(score: result[:score])

    analysis.completed!
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "AnalyzeGarmentJob: Analysis ##{analysis_id} introuvable — #{e.message}"
  rescue StandardError => e
    analysis&.failed!
    Rails.logger.error "AnalyzeGarmentJob: échec sur Analysis ##{analysis_id} — #{e.message}"
  end

  private

  # Choisit le service selon la variable d'environnement VISION_SERVICE.
  # "real" → vraie IA (GitHub Models). Sinon → stub (faux résultat).
  def vision_service
    ENV["VISION_SERVICE"] == "real" ? OpenaiVisionService : StubVisionService
  end
end
