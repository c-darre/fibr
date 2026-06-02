class AnalysesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :add_pictures, :show]

  def create
    # Crée une nouvelle analyse rattachée à l'utilisateur connecté (nil si anonyme)
    @analysis = Analysis.new(user: current_user)
    @analysis.save!

    # Crée immédiatement le chat associé (relation has_one)
    @analysis.create_chat!

    # Redirige vers l'étape suivante : upload des photos
    redirect_to add_pictures_analysis_path(@analysis)
  end

  def add_pictures
    # Charge l'analyse pour afficher le formulaire d'upload
    @analysis = Analysis.find(params[:id])
    # Objet vide nécessaire pour que form_with construise la bonne URL imbriquée
    @message = Message.new
  end

  def show
    # Charge l'analyse — la vue affichera un spinner ou les résultats selon le statut
    @analysis = Analysis.find(params[:id])
  end
end
