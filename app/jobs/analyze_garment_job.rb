class AnalyzeGarmentJob < ApplicationJob
  queue_as :default

  # STUB IA : données factices simulant une réponse d'analyse.
  # Aucun appel à OpenAI ou tout autre service externe n'est présent ici.
  STUB_CRITERIA = [
    { name: "Matière",   detail: "Qualité et composition du tissu détectées à l'analyse.",  score: 8 },
    { name: "Coupe",     detail: "Précision de la coupe et cohérence de la silhouette.",     score: 7 },
    { name: "Finitions", detail: "Qualité des coutures, ourlets et détails de confection.",  score: 9 }
  ].freeze

  def perform(analysis_id)
    # Récupère l'analyse depuis la base de données
    analysis = Analysis.find(analysis_id)

    # Simule le délai de traitement d'une vraie IA
    sleep 2

    # Crée un message "assistant" dans le chat pour matérialiser la réponse de l'IA
    analysis.chat.messages.create!(role: :assistant)

    # Crée les 3 critères d'évaluation factices liés à cette analyse
    STUB_CRITERIA.each do |attrs|
      analysis.criteria.create!(attrs)
    end

    # Passe l'analyse en statut "terminée" — la vue de résultats s'affichera au prochain rechargement
    analysis.completed!

  rescue ActiveRecord::RecordNotFound => e
    # L'analyse a été supprimée entre l'enfilage du job et son exécution
    Rails.logger.error "AnalyzeGarmentJob: Analysis ##{analysis_id} introuvable — #{e.message}"
  rescue StandardError => e
    # En cas d'erreur inattendue, on marque l'analyse comme échouée
    analysis&.failed!
    Rails.logger.error "AnalyzeGarmentJob: échec sur Analysis ##{analysis_id} — #{e.message}"
  end
end
