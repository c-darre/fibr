class MessagesController < ApplicationController
  skip_before_action :authenticate_user!

  def create
    # Retrouve l'analyse parente grâce à l'id imbriqué dans l'URL
    @analysis = Analysis.find(params[:analysis_id])
    chat = @analysis.chat

    # Construit le message utilisateur dans le chat
    message = chat.messages.build(role: :user)
    # Attache les photos uniquement si l'utilisateur en a soumis
    message.photos.attach(message_params[:photos]) if message_params[:photos].present?
    message.save!

    # Passe l'analyse en "traitement en cours"
    @analysis.processing!

    # Enfile le job d'analyse en arrière-plan via SolidQueue (pas d'appel synchrone)
    AnalyzeGarmentJob.perform_later(@analysis.id)

    # Redirige vers la page de résultats — elle se rafraîchira toutes les 3s automatiquement
    redirect_to analysis_path(@analysis)
  end

  private

  def message_params
    params.require(:message).permit(photos: [])
  end
end
